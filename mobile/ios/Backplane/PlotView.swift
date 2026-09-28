import MetalKit
import simd
import SwiftUI

// The board viewer: a plot on the GPU. A plot is uploaded once; panning,
// zooming and orbiting only move a transform, so every frame costs the
// same however big the board. Frames are drawn on demand: while a finger
// moves, a fade runs or a fling coasts, and never otherwise.

private struct Uniforms {
    var size: SIMD2<Float>
    var off: SIMD2<Float>
    var scale: Float
    var fade: Float
    var z: Float = 0
    var focal: Float = 0
    var color: SIMD4<Float>
    var mvp = matrix_identity_float4x4
    var light = SIMD4<Float>(0, 0, 1, 0)
}

// one layer's share of the buffers: capsules and fill vertices, the chunks
// already shown first, then those fading in
private struct LayerDraw {
    var layer: Int
    var color: SIMD4<Float>
    var caps: Range<Int>
    var freshCaps: Range<Int>
    var tris: Range<Int>
    var freshTris: Range<Int>
}

// a 3D camera turning freely about a pivot (a board's rectangle's centre), like
// SolidWorks, in a right-handed world where the board's y is flipped
// (KiCad's y points down the screen), micrometres. r, u, f: the view's
// right, up and forward; pan: in the view plane; dist: from the eye to the
// pivot's depth
struct Orbit {
    var pivot = SIMD3<Float>(0, 0, 0)
    var r = SIMD3<Float>(1, 0, 0)
    var u = SIMD3<Float>(0, 0, 1)
    var f = SIMD3<Float>(0, 1, 0)
    var pan = SIMD2<Float>(0, 0)
    var dist: Float = 100_000
    var fov: Float = 35

    var target: SIMD3<Float> { pivot + r * pan.x + u * pan.y }
    var eye: SIMD3<Float> { target - f * dist }

    // world units per point (or pixel) at the pivot's depth, in a view h tall
    func unit(_ h: Float) -> Float { dist * 2 * tan(fov * .pi / 360) / max(h, 1) }

    // looking at the pivot from yaw and pitch (radians), world z up
    mutating func aim(yaw: Float, pitch: Float) {
        f = SIMD3(-sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), -sin(pitch))
        u = SIMD3(0, 0, 1)
        square()
    }

    // orthonormal again (no drift): f, then r = f x u, u = r x f
    private mutating func square() {
        f = simd_normalize(f)
        r = simd_normalize(simd_cross(f, u))
        u = simd_normalize(simd_cross(r, f))
    }

    // the view turned by a about a unit axis (the model turns by -a)
    private mutating func turn(_ k: SIMD3<Float>, _ a: Float) {
        let q = simd_quatf(angle: a, axis: k)
        r = q.act(r)
        u = q.act(u)
        f = q.act(f)
        square()
    }

    // a finger moved m on screen, radians per unit: the model under it follows
    mutating func spin(_ m: SIMD2<Float>, _ k: Float) {
        let l = simd_length(m)
        guard l > 1e-6 else { return }
        turn((u * m.x + r * m.y) / l, -l * k)
    }

    // the model turned clockwise on screen by a
    mutating func roll(_ a: Float) { turn(f, -a) }

    // the point under the fingers at the pivot's depth moves with them (s: world per unit)
    mutating func move(_ m: SIMD2<Float>, _ s: Float) { pan += SIMD2(-m.x, m.y) * s }

    // dist over k, keeping the point at p (world units from the view's centre) where it is
    mutating func zoom(_ k: Float, _ p: SIMD2<Float>) {
        let d = min(max(dist / k, 2_000), 5_000_000)
        pan += p * (1 - d / dist)
        dist = d
    }

    func proj(_ aspect: Float) -> float4x4 {
        let f = 1 / tan(fov * .pi / 360), n = max(dist * 0.01, 1), fa = dist * 20 + 1_000_000
        return float4x4(columns: (SIMD4(f / aspect, 0, 0, 0), SIMD4(0, f, 0, 0), SIMD4(0, 0, fa / (n - fa), -1), SIMD4(0, 0, n * fa / (n - fa), 0)))
    }

    var view: float4x4 {
        let e = eye
        return float4x4(columns: (SIMD4(r.x, u.x, -f.x, 0), SIMD4(r.y, u.y, -f.y, 0), SIMD4(r.z, u.z, -f.z, 0),
                                  SIMD4(-simd_dot(r, e), -simd_dot(u, e), simd_dot(f, e), 1)))
    }

    // board micrometres to clip space
    func mvp(_ aspect: Float) -> float4x4 {
        proj(aspect) * view * float4x4(diagonal: SIMD4(1, -1, 1, 1))
    }
}

@MainActor
final class PlotRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let lib: MTLLibrary
    private var pipes: [String: MTLRenderPipelineState] = [:]
    private let plain, stencilWrite, stencilCover, depthRead, depthWrite, depthStencilWrite, depthStencilCover: MTLDepthStencilState
    private var capBuf, triBuf, meshBuf, colorBuf, hiCaps, hiTris, slabBuf, colorSlab: MTLBuffer?
    private var layers: [LayerDraw] = []
    private var meshCount = 0
    private var hiCount = (0, 0)
    private var hiLayer = -1
    private var slabCount = 0
    private var cov, stencil, depth, msColor, msDepth: MTLTexture?
    // the model's multisampling (4x where the GPU has it)
    private let samples: Int
    var bg = SIMD4<Float>(0, 0, 0, 1)
    // each layer's colour on the viewer's light ground (empty: the chunks' own)
    var look: [UInt32] = []
    // the layers the user turned off, a bit each
    var hiddenLayers: UInt32 = 0
    func shown(_ layer: Int) -> Bool { layer < 0 || layer > 31 || (hiddenLayers >> UInt32(layer)) & 1 == 0 }
    // 2D view: pixels per micrometre and where 0,0 lands, in points
    var scale: Float = 0.01
    var off = SIMD2<Float>(0, 0)
    var fade: Float = 1
    // 3D
    var three = false
    var orbit = Orbit()
    var thick: Float = 1600
    var top: [Int] = []
    var bottom: [Int] = []

    private static var compiled: MTLLibrary?

    private static func library(_ d: MTLDevice) -> MTLLibrary? {
        if let l = compiled { return l }
        do {
            compiled = try d.makeLibrary(source: PlotShaders.source, options: nil)
        } catch {
            NSLog("plot shaders: %@", "\(error)")
        }
        return compiled
    }

    init?(view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue(), let l = Self.library(d) else { return nil }
        device = d
        queue = q
        lib = l
        view.device = d
        view.colorPixelFormat = .bgra8Unorm
        samples = [4, 2].first { d.supportsTextureSampleCount($0) } ?? 1
        func ds(_ f: (MTLDepthStencilDescriptor) -> Void) -> MTLDepthStencilState { let x = MTLDepthStencilDescriptor(); f(x); return d.makeDepthStencilState(descriptor: x)! }
        // nonzero winding: counter-clockwise triangles count up, others down
        func windUp(_ x: MTLDepthStencilDescriptor) {
            let up = MTLStencilDescriptor(), down = MTLStencilDescriptor()
            up.depthStencilPassOperation = .incrementWrap
            down.depthStencilPassOperation = .decrementWrap
            x.frontFaceStencil = up
            x.backFaceStencil = down
        }
        // cover where the count is not zero, and zero it again
        func cover(_ x: MTLDepthStencilDescriptor) {
            let s = MTLStencilDescriptor()
            s.stencilCompareFunction = .notEqual
            s.depthStencilPassOperation = .zero
            x.frontFaceStencil = s
            x.backFaceStencil = s
        }
        plain = ds { _ in }
        stencilWrite = ds(windUp)
        stencilCover = ds(cover)
        depthRead = ds { $0.depthCompareFunction = .lessEqual }
        depthWrite = ds { $0.depthCompareFunction = .less; $0.isDepthWriteEnabled = true }
        depthStencilWrite = ds { $0.depthCompareFunction = .lessEqual; windUp($0) }
        depthStencilCover = ds { $0.depthCompareFunction = .lessEqual; cover($0) }
        super.init()
    }

    // a pipeline: vertex and fragment functions, the target (coverage or
    // the frame), writing or not, blending by max (coverage) or over; in 3D
    // with depth
    private func pipe(_ v: String, _ f: String, cov: Bool, write: Bool = true, three: Bool, samples n: Int = 1) -> MTLRenderPipelineState {
        let key = "\(v)|\(f)|\(cov)|\(write)|\(three)|\(n)"
        if let p = pipes[key] { return p }
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = lib.makeFunction(name: v)
        p.fragmentFunction = lib.makeFunction(name: f)
        let c = p.colorAttachments[0]!
        c.pixelFormat = cov ? .r8Unorm : .bgra8Unorm
        c.writeMask = write ? .all : []
        if write && f != "mesh_f" {
            c.isBlendingEnabled = true
            if cov {
                c.rgbBlendOperation = .max
                c.alphaBlendOperation = .max
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationAlphaBlendFactor = .one
            } else {
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
        if n > 1 {
            // the model's multisampled pass: depth, no stencil
            p.rasterSampleCount = n
            p.depthAttachmentPixelFormat = .depth32Float
        } else if three {
            p.depthAttachmentPixelFormat = .depth32Float_stencil8
            p.stencilAttachmentPixelFormat = .depth32Float_stencil8
        } else if cov {
            p.stencilAttachmentPixelFormat = .stencil8
        }
        let s = try! device.makeRenderPipelineState(descriptor: p)
        pipes[key] = s
        return s
    }

    private func buffer(_ a: [Float]) -> MTLBuffer? {
        a.isEmpty ? nil : device.makeBuffer(bytes: a, length: a.count * 4, options: .storageModeShared)
    }

    // a plot's chunks into two buffers, layer by layer (the hub sends them
    // in paint order)
    func load(_ chunks: [PlotChunk], fresh: Set<Int>) {
        var caps: [Float] = [], tris: [Float] = []
        caps.reserveCapacity(chunks.reduce(0) { $0 + $1.caps.count })
        tris.reserveCapacity(chunks.reduce(0) { $0 + $1.tris.count })
        var out: [LayerDraw] = []
        var i = 0
        while i < chunks.count {
            let first = chunks[i]
            var j = i
            while j < chunks.count, chunks[j].layer == first.layer { j += 1 }
            let c0 = caps.count / 5, t0 = tris.count / 2
            for k in i..<j where !fresh.contains(k) { caps += chunks[k].caps; tris += chunks[k].tris }
            let c1 = caps.count / 5, t1 = tris.count / 2
            for k in i..<j where fresh.contains(k) { caps += chunks[k].caps; tris += chunks[k].tris }
            let rgb = first.layer >= 0 && first.layer < look.count ? look[first.layer] : first.color
            out.append(LayerDraw(layer: first.layer,
                color: SIMD4(Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, first.alpha),
                caps: c0..<c1, freshCaps: c1..<(caps.count / 5), tris: t0..<t1, freshTris: t1..<(tris.count / 2)))
            i = j
        }
        capBuf = buffer(caps)
        triBuf = buffer(tris)
        layers = out
    }

    func load(mesh m: PlotMesh?) {
        guard let m, !m.colors.isEmpty else { meshBuf = nil; colorBuf = nil; meshCount = 0; return }
        meshBuf = buffer(m.verts)
        colorBuf = device.makeBuffer(bytes: m.colors, length: m.colors.count * 4, options: .storageModeShared)
        meshCount = m.colors.count
    }

    // the board as a plain slab (before its model arrives)
    func slab(_ box: [Float], color: UInt32) {
        guard box.count == 4 else { slabBuf = nil; slabCount = 0; return }
        let (x0, y0, x1, y1, z0, z1) = (box[0], box[1], box[2], box[3], Float(0), thick)
        let p: [SIMD3<Float>] = [SIMD3(x0, y0, z0), SIMD3(x1, y0, z0), SIMD3(x1, y1, z0), SIMD3(x0, y1, z0),
                                 SIMD3(x0, y0, z1), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1)]
        let faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        var v: [Float] = [], c: [UInt32] = []
        for f in faces {
            let n = simd_normalize(simd_cross(p[f[1]] - p[f[0]], p[f[2]] - p[f[0]]))
            for k in [0, 1, 2, 0, 2, 3] { let q = p[f[k]]; v += [q.x, q.y, q.z, n.x, n.y, n.z]; c.append(color) }
        }
        slabBuf = buffer(v)
        colorSlab = device.makeBuffer(bytes: c, length: c.count * 4, options: .storageModeShared)
        slabCount = c.count
    }

    // the picked piece, drawn bright over everything
    func highlight(_ c: PlotChunk?, _ p: PlotChunk.Piece?) {
        guard let c, let p else { hiCaps = nil; hiTris = nil; hiCount = (0, 0); hiLayer = -1; return }
        hiCaps = buffer(Array(c.caps[(p.caps.lowerBound * 5)..<(p.caps.upperBound * 5)]))
        hiTris = buffer(Array(c.tris[(p.tris.lowerBound * 6)..<(p.tris.upperBound * 6)]))
        hiCount = (p.caps.count, p.tris.count * 3)
        hiLayer = c.layer
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cov = nil
    }

    private func targets(_ w: Int, _ h: Int) {
        if let c = cov, c.width == w, c.height == h { return }
        func tex(_ f: MTLPixelFormat, _ u: MTLTextureUsage, _ m: MTLStorageMode, samples n: Int = 1) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
            d.usage = u
            d.storageMode = m
            if n > 1 {
                d.textureType = .type2DMultisample
                d.sampleCount = n
            }
            return device.makeTexture(descriptor: d)
        }
        cov = tex(.r8Unorm, [.renderTarget, .shaderRead], .private)
        stencil = tex(.stencil8, .renderTarget, .memoryless)
        depth = tex(.depth32Float_stencil8, .renderTarget, .private)
        if samples > 1 {
            msColor = tex(.bgra8Unorm, .renderTarget, .memoryless, samples: samples)
            msDepth = tex(.depth32Float, .renderTarget, .memoryless, samples: samples)
        }
    }

    private func frame(_ cb: MTLCommandBuffer, _ t: MTLTexture, clear: Bool, depth d: Bool, _ f: (MTLRenderCommandEncoder) -> Void) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = t
        pass.colorAttachments[0].loadAction = clear ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        if d {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .store
            pass.stencilAttachment.texture = depth
            pass.stencilAttachment.loadAction = .clear
            pass.stencilAttachment.storeAction = .store
        }
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        f(e)
        e.endEncoding()
    }

    // one layer's coverage (fills by stencil, then capsules), laid over the frame
    private func layer(_ cb: MTLCommandBuffer, _ drawable: MTLTexture, _ u: inout Uniforms, color: SIMD4<Float>,
                       caps: [(MTLBuffer?, Range<Int>, Float)], tris: [(MTLBuffer?, Range<Int>, Float)]) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = cov
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        if three {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .load
            pass.depthAttachment.storeAction = .store
            pass.stencilAttachment.texture = depth
        } else {
            pass.stencilAttachment.texture = stencil
        }
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = three ? .store : .dontCare
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        e.setFrontFacing(.counterClockwise)
        e.setCullMode(.none)
        let fillV = three ? "fill3_v" : "fill_v", capV = three ? "cap3_v" : "cap_v"
        for (b, r, f) in tris where !r.isEmpty && b != nil {
            u.fade = f
            e.setVertexBuffer(b, offset: r.lowerBound * 8, index: 0)
            e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.setRenderPipelineState(pipe(fillV, "fill_f", cov: true, write: false, three: three))
            e.setDepthStencilState(three ? depthStencilWrite : stencilWrite)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.count)
            e.setRenderPipelineState(pipe(fillV, "fill_f", cov: true, three: three))
            e.setDepthStencilState(three ? depthStencilCover : stencilCover)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.count)
        }
        e.setRenderPipelineState(pipe(capV, "cap_f", cov: true, three: three))
        e.setDepthStencilState(three ? depthRead : plain)
        for (b, r, f) in caps where !r.isEmpty && b != nil {
            u.fade = f
            e.setVertexBuffer(b, offset: r.lowerBound * 20, index: 0)
            e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: r.count)
        }
        e.endEncoding()
        frame(cb, drawable, clear: false, depth: false) { q in
            u.color = color
            q.setRenderPipelineState(pipe("quad_v", "quad_f", cov: false, three: false))
            q.setFragmentTexture(cov, index: 0)
            q.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            q.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    private func draws(_ l: LayerDraw) -> ([(MTLBuffer?, Range<Int>, Float)], [(MTLBuffer?, Range<Int>, Float)]) {
        ([(capBuf, l.caps, 1), (capBuf, l.freshCaps, fade)], [(triBuf, l.tris, 1), (triBuf, l.freshTris, fade)])
    }

    private func hi(_ cb: MTLCommandBuffer, _ t: MTLTexture, _ u: inout Uniforms) {
        guard hiCount.0 + hiCount.1 > 0 else { return }
        layer(cb, t, &u, color: SIMD4(1, 1, 1, 0.8), caps: [(hiCaps, 0..<hiCount.0, 1)], tris: [(hiTris, 0..<hiCount.1, 1)])
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        guard encode(cb, into: drawable.texture, k: Float(view.pixelScale)) else { return }
        cb.present(drawable)
        cb.commit()
    }

    // One frame of the view drawn offscreen, as draw(in:) draws it on the
    // screen: a Metal layer shows only on a screen, so this is what a
    // snapshot of the viewer takes (BackplaneTests).
    func image(of view: MTKView) -> CGImage? {
        let w = Int(view.drawableSize.width), h = Int(view.drawableSize.height)
        guard w > 0, h > 0, let cb = queue.makeCommandBuffer() else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d), encode(cb, into: t, k: Float(view.pixelScale)) else { return nil }
        cb.commit()
        cb.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: w * h * 4)
        t.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let data = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: data, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // the frame into t (w by h pixels, k pixels a point); false when there is nothing to draw into
    private func encode(_ cb: MTLCommandBuffer, into t: MTLTexture, k: Float) -> Bool {
        let w = t.width, h = t.height
        guard w > 0, h > 0 else { return false }
        targets(w, h)
        var u = Uniforms(size: SIMD2(Float(w), Float(h)), off: off * k, scale: scale * k, fade: 1, color: .zero)
        if three {
            u.mvp = orbit.mvp(Float(w) / Float(h))
            u.focal = 1 / tan(orbit.fov * .pi / 360) * Float(h) / 2
            // lit from the viewer (model space: y flipped)
            u.light = SIMD4(-orbit.f.x, orbit.f.y, -orbit.f.z, 0)
            // the model (or a slab) with depth, then the faces' layers over it
            let (mb, cbuf, mc) = meshCount > 0 ? (meshBuf, colorBuf, meshCount) : (slabBuf, colorSlab, slabCount)
            let dw = depthWrite
            func model(_ e: MTLRenderCommandEncoder, _ p: MTLRenderPipelineState) {
                e.setFrontFacing(.counterClockwise)
                e.setCullMode(.none)
                e.setDepthStencilState(dw)
                e.setRenderPipelineState(p)
                e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                guard mc > 0, let mb, let cbuf else { return }
                e.setVertexBuffer(mb, offset: 0, index: 0)
                e.setVertexBuffer(cbuf, offset: 0, index: 2)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mc)
            }
            if samples > 1, let mcol = msColor, let mdep = msDepth {
                // multisampled and resolved into the frame; the layers test
                // against the model's depth drawn again single-sampled
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = mcol
                pass.colorAttachments[0].resolveTexture = t
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
                pass.colorAttachments[0].storeAction = .multisampleResolve
                pass.depthAttachment.texture = mdep
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.clearDepth = 1
                pass.depthAttachment.storeAction = .dontCare
                let ms = pipe("mesh_v", "mesh_f", cov: false, three: true, samples: samples)
                if let e = cb.makeRenderCommandEncoder(descriptor: pass) {
                    model(e, ms)
                    e.endEncoding()
                }
                let dp = pipe("mesh_v", "mesh_f", cov: false, write: false, three: true)
                frame(cb, t, clear: false, depth: true) { e in model(e, dp) }
            } else {
                let mp = pipe("mesh_v", "mesh_f", cov: false, three: true)
                frame(cb, t, clear: true, depth: true) { e in model(e, mp) }
            }
            for (face, z) in [(top, thick + 40), (bottom, Float(-40))] {
                u.z = z
                for id in face {
                    for l in layers where l.layer == id && shown(l.layer) {
                        let (c, tr) = draws(l)
                        layer(cb, t, &u, color: l.color, caps: c, tris: tr)
                    }
                }
                if face.contains(hiLayer) { hi(cb, t, &u) }
            }
        } else {
            frame(cb, t, clear: true, depth: false) { _ in }
            for l in layers where shown(l.layer) {
                let (c, tr) = draws(l)
                layer(cb, t, &u, color: l.color, caps: c, tris: tr)
            }
            hi(cb, t, &u)
        }
        return true
    }
}

// The view: gestures move the transform; a display link runs only while
// something moves by itself (a fade, a fling). A tap asks what lies under
// the finger.
final class PlotCanvas: MTKView {
    var renderer: PlotRenderer!
    var box: [Float] = []
    // the board's rectangle: the 3D view turns about its centre
    var edge: [Float] = []
    var margin: Float = 0.9
    var zmin: Float = 0.5
    var zmax: Float = 0.5
    var tap: Float = 14
    var fadeMs: Double = 220
    var chunks: [PlotChunk] = []
    var onPick: (String) -> Void = { _ in }
    private var fitted = false
    private var shownKey = ""
    private var fadeFrom: Date?
    private var fling = SIMD2<Float>(0, 0)
    private var link: CADisplayLink?
    private var lastTick = CACurrentMediaTime()

    init?(canvas frame: CGRect) {
        super.init(frame: frame, device: nil)
        guard let r = PlotRenderer(view: self) else { return nil }
        renderer = r
        delegate = r
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 120
        #if os(iOS)
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 2
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(twisted(_:)))
        let twice = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        twice.numberOfTapsRequired = 2
        let once = UITapGestureRecognizer(target: self, action: #selector(picked(_:)))
        once.require(toFail: twice)
        for g in [pinch, pan, twist, twice, once] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
        #endif
    }

    required init(coder: NSCoder) { fatalError() }

    #if os(iOS)
    // every physical pixel (the default scale can be below the panel's)
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let s = window?.windowScene?.screen { contentScaleFactor = s.nativeScale }
    }

    func redraw() {
        setNeedsDisplay()
        #if DEBUG
        still()
        #endif
    }
    private func relayout() { setNeedsLayout() }
    #else
    // y grows down, as on iOS: the board's transforms are shared
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func redraw() {
        needsDisplay = true
        #if DEBUG
        still()
        #endif
    }
    private func relayout() { needsLayout = true }
    #endif

    #if DEBUG
    // Under BackplaneTests the canvas also shows its frame as a still
    // image over itself: a Metal layer draws only on a screen, so this is
    // what a snapshot takes (the frame as it is once any fade is done).
    #if os(iOS)
    private var stillView: UIImageView?
    #else
    private var stillView: NSImageView?
    #endif

    private func still() {
        // (at once: a test waiting on the main actor never lets queued work run)
        guard Platform.testing, drawableSize.width > 0 else { return }
        renderer.fade = 1
        guard let img = renderer.image(of: self) else { return }
        #if os(iOS)
        let v = stillView ?? UIImageView()
        v.image = UIImage(cgImage: img, scale: pixelScale, orientation: .up)
        #else
        let v = stillView ?? NSImageView()
        v.imageScaling = .scaleAxesIndependently
        v.image = NSImage(cgImage: img, size: bounds.size)
        #endif
        v.frame = bounds
        if stillView == nil {
            addSubview(v)
            stillView = v
        }
    }
    #endif

    private var three: Bool { renderer.three }

    // the zoom that shows the whole box, and the range around it
    private var fit: Float {
        guard box.count == 4 else { return renderer.scale }
        let w = Float(bounds.width), h = Float(bounds.height)
        return margin * min(w / max(box[2] - box[0], 1), h / max(box[3] - box[1], 1))
    }

    func refit() {
        guard box.count == 4, bounds.width > 0 else { return }
        let s = fit
        renderer.scale = s
        renderer.off = SIMD2(Float(bounds.width) / 2 - (box[0] + box[2]) / 2 * s, Float(bounds.height) / 2 - (box[1] + box[3]) / 2 * s)
        var o = Orbit(fov: renderer.orbit.fov)
        let e = edge.count == 4 ? edge : box
        let cx = (e[0] + e[2]) / 2, cy = (e[1] + e[3]) / 2
        o.pivot = SIMD3(cx, -cy, renderer.thick / 2)
        o.aim(yaw: 0.5, pitch: 0.75)
        // far enough to show the whole box round the pivot
        let reach = simd_length(SIMD2(max(abs(box[0] - cx), abs(box[2] - cx)), max(abs(box[1] - cy), abs(box[3] - cy))))
        // the narrower of the two fields of view takes the whole board
        let half = tan(o.fov * .pi / 360), aspect = Float(bounds.width) / Float(max(bounds.height, 1))
        o.dist = reach / (half * min(aspect, 1)) * 1.1
        renderer.orbit = o
        fitted = true
        redraw()
    }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        if !fitted { refit() }
        #if DEBUG
        still()
        #endif
    }
    #else
    override func layout() {
        super.layout()
        if !fitted { refit() }
        #if DEBUG
        still()
        #endif
    }
    #endif

    func show(_ f: PlotFrame, bg: UInt32, slab: UInt32, look: [UInt32]) {
        renderer.bg = SIMD4(Float((bg >> 16) & 255) / 255, Float((bg >> 8) & 255) / 255, Float(bg & 255) / 255, 1)
        renderer.look = look
        renderer.thick = f.thick > 0 ? f.thick : 1600
        renderer.load(f.chunks, fresh: f.fresh)
        chunks = f.chunks
        // a new source (board to schematic, another sheet) fits anew
        let first = box.isEmpty || !fitted || f.key != shownKey
        shownKey = f.key
        box = f.box
        edge = f.edge.count == 4 && f.edge[0] <= f.edge[2] ? f.edge : f.box
        renderer.slab(edge, color: slab)
        if first { fitted = false; relayout() }
        fadeFrom = f.fresh.isEmpty ? nil : f.at
        renderer.fade = f.fresh.isEmpty ? 1 : 0
        run()
        redraw()
    }

    // the picked piece ("chunk,info" of the held chunks), drawn bright
    func mark(_ picked: String) {
        let ps = picked.split(separator: ",").compactMap { Int($0) }
        if ps.count == 2, ps[0] < chunks.count, let p = chunks[ps[0]].pieces.first(where: { $0.info == ps[1] }) {
            renderer.highlight(chunks[ps[0]], p)
        } else {
            renderer.highlight(nil, nil)
        }
        redraw()
    }

    private func zoom(by f: Float, at p: CGPoint) {
        if three {
            // toward the point under the fingers
            let s = renderer.orbit.unit(Float(bounds.height))
            renderer.orbit.zoom(f, SIMD2(Float(p.x - bounds.width / 2), Float(bounds.height / 2 - p.y)) * s)
            return
        }
        let s0 = renderer.scale
        let s = min(max(s0 * f, fit * zmin), max(zmax, fit))
        let k = s / s0
        let a = SIMD2(Float(p.x), Float(p.y))
        renderer.off = a - (a - renderer.off) * k
        renderer.scale = s
    }

    #if os(iOS)
    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        zoom(by: Float(g.scale), at: g.location(in: self))
        g.scale = 1
        redraw()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        if three {
            // one finger turns the model under it, two move it with them
            var o = renderer.orbit
            let m = SIMD2(Float(t.x), Float(t.y))
            if g.numberOfTouches >= 2 { o.move(m, o.unit(Float(bounds.height))) } else { o.spin(m, 0.008) }
            renderer.orbit = o
            redraw()
            return
        }
        renderer.off += SIMD2(Float(t.x), Float(t.y))
        if g.state == .began { fling = .zero }
        if g.state == .ended {
            let v = g.velocity(in: self)
            fling = SIMD2(Float(v.x), Float(v.y))
            run()
        }
        redraw()
    }

    // two fingers twisting roll the model about the view axis
    @objc private func twisted(_ g: UIRotationGestureRecognizer) {
        let a = Float(g.rotation)
        g.rotation = 0
        guard three else { return }
        renderer.orbit.roll(a)
        redraw()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        doubled(at: g.location(in: self))
    }

    @objc private func picked(_ g: UITapGestureRecognizer) {
        tap(at: g.location(in: self))
    }
    #endif

    // a double tap or click: fit the 3D view or a zoomed board, else zoom in there
    private func doubled(at p: CGPoint) {
        if three || renderer.scale > fit * 1.5 { refit() } else { zoom(by: 3, at: p) }
        redraw()
    }

    // where on the board a point of the view lands (micrometres), and on
    // which face's layers in 3D (the face toward the viewer)
    private func board(_ p: CGPoint) -> (SIMD2<Float>, [Int]?)? {
        guard three else {
            return ((SIMD2(Float(p.x), Float(p.y)) - renderer.off) / renderer.scale, nil)
        }
        let w = Float(bounds.width), h = Float(bounds.height)
        let inv = renderer.orbit.mvp(w / h).inverse
        let n = SIMD2(Float(p.x) / w * 2 - 1, 1 - Float(p.y) / h * 2)
        func at(_ z: Float) -> SIMD3<Float> { let q = inv * SIMD4(n.x, n.y, z, 1); return SIMD3(q.x, q.y, q.z) / q.w }
        let a = at(0), b = at(1)
        let above = renderer.orbit.eye.z > renderer.thick / 2
        let z = above ? renderer.thick + 40 : -40
        guard abs(b.z - a.z) > 1e-6 else { return nil }
        let t = (z - a.z) / (b.z - a.z)
        guard t > 0 else { return nil }
        let q = a + (b - a) * t
        return (SIMD2(q.x, q.y), above ? renderer.top : renderer.bottom)
    }

    // what lies under a point, for Bend to pick from (View.pick)
    func tap(at p: CGPoint) {
        guard let (q, face) = board(p) else { onPick("[]"); return }
        // the finger's reach, in micrometres
        let tol: Float
        if three {
            tol = tap * renderer.orbit.unit(Float(bounds.height))
        } else {
            tol = tap / renderer.scale
        }
        var cands: [[String: Any]] = []
        for (ci, c) in chunks.enumerated() {
            if let face, !face.contains(c.layer) { continue }
            for piece in c.pieces {
                let b = piece.box
                guard q.x >= b.x - tol, q.x <= b.z + tol, q.y >= b.y - tol, q.y <= b.w + tol else { continue }
                guard c.distance(piece, q.x, q.y) <= tol else { continue }
                let area = max(b.z - b.x, 1) * max(b.w - b.y, 1) / 100
                cands.append(["c": ci, "p": piece.info, "a": Int(min(area, 4e9)), "l": c.layer])
            }
        }
        let json = (try? JSONSerialization.data(withJSONObject: cands)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        onPick(json)
    }

    #if os(macOS)
    // The Mac reads the mouse, the trackpad and the keys the way the desktop
    // viewer does (docs/parity.md): a drag turns the 3D model (ctrl pans,
    // shift zooms, alt rolls) or moves the board; a mouse wheel zooms at
    // the pointer, forward out; two fingers on a trackpad move the board
    // (or turn the model), pinch and twist; keys 1-7 are the standard views,
    // arrows turn 15 degrees (90 with shift), z and shift+z zoom, f fits.
    private var press = CGPoint.zero
    private var last = CGPoint.zero
    private var dragged = false
    private var pending: DispatchWorkItem?

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func down(_ e: NSEvent) {
        window?.makeFirstResponder(self)
        press = point(e)
        last = press
        dragged = false
    }

    override func mouseDown(with e: NSEvent) {
        down(e)
        if e.clickCount == 2 {
            pending?.cancel()
            pending = nil
            doubled(at: press)
        }
    }

    override func mouseUp(with e: NSEvent) {
        guard !dragged, e.clickCount == 1 else { return }
        // a single click inspects once a second click can no longer follow
        let p = point(e)
        let w = DispatchWorkItem { [weak self] in self?.tap(at: p) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: w)
    }

    override func mouseDragged(with e: NSEvent) { drag(e, pan: false) }
    override func otherMouseDown(with e: NSEvent) { down(e) }
    override func otherMouseDragged(with e: NSEvent) { drag(e, pan: false) }
    // a right drag moves the view, like ctrl
    override func rightMouseDown(with e: NSEvent) { down(e) }
    override func rightMouseDragged(with e: NSEvent) { drag(e, pan: true) }

    private func drag(_ e: NSEvent, pan: Bool) {
        let p = point(e)
        let m = SIMD2(Float(p.x - last.x), Float(p.y - last.y))
        last = p
        dragged = true
        pending?.cancel()
        let mods = e.modifierFlags
        if mods.contains(.shift) {
            // up is in, about the press
            zoom(by: exp(-m.y * 0.006), at: press)
        } else if three {
            var o = renderer.orbit
            if pan || mods.contains(.control) {
                o.move(m, o.unit(Float(bounds.height)))
            } else if mods.contains(.option) {
                o.roll(m.x * 0.01)
            } else {
                o.spin(m, 0.008)
            }
            renderer.orbit = o
        } else {
            renderer.off += m
        }
        redraw()
    }

    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            // a trackpad's two fingers: the board moves with them, the model turns
            let m = SIMD2(Float(e.scrollingDeltaX), Float(e.scrollingDeltaY))
            if three { renderer.orbit.spin(m, 0.008) } else { renderer.off += m }
        } else {
            // a mouse wheel (or cmd+scroll): the physical forward turn zooms out
            let d = Float(e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY)
            guard d != 0 else { return }
            zoom(by: d > 0 ? 1 / 1.2 : 1.2, at: point(e))
        }
        redraw()
    }

    override func magnify(with e: NSEvent) {
        zoom(by: Float(1 + e.magnification), at: point(e))
        redraw()
    }

    // counter-clockwise degrees; the model turns with the fingers
    override func rotate(with e: NSEvent) {
        guard three else { return }
        renderer.orbit.roll(-Float(e.rotation) * .pi / 180)
        redraw()
    }

    override func keyDown(with e: NSEvent) {
        let big = e.modifierFlags.contains(.shift)
        let a: Float = big ? .pi / 2 : .pi / 12
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        func turn(_ dx: Float, _ dy: Float) {
            if three {
                renderer.orbit.spin(SIMD2(dx, dy), a)
            } else {
                renderer.off += SIMD2(-dx, -dy) * 48
            }
        }
        switch e.specialKey {
        case .leftArrow?: turn(-1, 0)
        case .rightArrow?: turn(1, 0)
        case .upArrow?: turn(0, -1)
        case .downArrow?: turn(0, 1)
        default:
            switch e.charactersIgnoringModifiers ?? "" {
            case "f", "F": refit()
            case "z": zoom(by: 1 / 1.25, at: centre)
            case "Z": zoom(by: 1.25, at: centre)
            case let k where three && k.count == 1 && ("1" ... "7").contains(k):
                // front, back, left, right, top, bottom, isometric (nearly
                // straight down or up: aim needs a side to call right)
                let side: Float = .pi / 2 - 0.001
                let views: [(Float, Float)] = [(0, 0), (.pi, 0), (-.pi / 2, 0), (.pi / 2, 0), (0, side), (0, -side), (.pi / 4, 0.6154797)]
                let v = views[Int(k)! - 1]
                renderer.orbit.aim(yaw: v.0, pitch: v.1)
            default:
                super.keyDown(with: e)
                return
            }
        }
        redraw()
    }
    #endif

    private func run() {
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        #if os(iOS)
        let l = CADisplayLink(target: self, selector: #selector(tick))
        #else
        let l = displayLink(target: self, selector: #selector(tick))
        #endif
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = Float(now - lastTick)
        lastTick = now
        var busy = false
        if let t0 = fadeFrom {
            let f = Float(min(1, Date().timeIntervalSince(t0) * 1000 / fadeMs))
            renderer.fade = f
            if f >= 1 { fadeFrom = nil } else { busy = true }
        }
        if simd_length(fling) > 8 {
            renderer.off += fling * dt
            fling *= pow(0.004, dt)
            busy = true
        } else {
            fling = .zero
        }
        redraw()
        if !busy {
            link?.invalidate()
            link = nil
        }
    }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }
}

#if os(iOS)
extension PlotCanvas: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif

extension MTKView {
    // pixels per point, for turning the view's point-space transform into the drawable's
    var pixelScale: CGFloat {
        #if os(iOS)
        contentScaleFactor
        #else
        bounds.width > 0 ? drawableSize.width / bounds.width : (window?.backingScaleFactor ?? 2)
        #endif
    }
}

struct PlotCanvasView {
    let frame: PlotFrame?
    let mesh: MeshFrame?
    let viewer: Viewer
    let pick: (String) -> Void

    @MainActor fileprivate func update(_ c: PlotCanvas, _ context: Coordinator) {
        c.margin = viewer.margin
        c.zmin = viewer.zmin
        c.zmax = viewer.zmax
        c.tap = viewer.tap
        c.fadeMs = Double(viewer.fade)
        c.onPick = pick
        c.renderer.top = viewer.top
        c.renderer.bottom = viewer.bottom
        c.renderer.orbit.fov = viewer.fov
        let three = viewer.open == "3d"
        if c.renderer.three != three {
            c.renderer.three = three
            c.refit()
        }
        if c.renderer.hiddenLayers != (viewer.off ?? 0) {
            c.renderer.hiddenLayers = viewer.off ?? 0
            c.redraw()
        }
        if let f = frame, f.at != context.shown || (viewer.look ?? []) != context.look {
            context.shown = f.at
            context.look = viewer.look ?? []
            c.show(f, bg: viewer.bg, slab: viewer.slab, look: viewer.look ?? [])
            #if DEBUG
            // headless checks: SIMCTL_CHILD_BACKPLANE_TAP=x,y (points) taps there once
            if let t = ProcessInfo.processInfo.environment["BACKPLANE_TAP"], !context.tapped {
                context.tapped = true
                let xy = t.split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.tap(at: CGPoint(x: xy[0], y: xy[1])) } }
            }
            #endif
        }
        if three, let m = mesh, m.at != context.mesh {
            context.mesh = m.at
            c.renderer.load(mesh: m.mesh)
            c.redraw()
        }
        if viewer.picked != context.picked {
            context.picked = viewer.picked
            c.mark(viewer.picked)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: Date?
        var look: [UInt32] = []
        var mesh: Date?
        var picked = ""
        var tapped = false
    }
}

#if os(iOS)
extension PlotCanvasView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        guard let c = PlotCanvas(canvas: .zero) else {
            let l = UILabel()
            l.text = "This device has no Metal."
            l.textAlignment = .center
            return l
        }
        return c
    }

    func updateUIView(_ v: UIView, context: Context) {
        if let c = v as? PlotCanvas { update(c, context.coordinator) }
    }
}
#else
extension PlotCanvasView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        guard let c = PlotCanvas(canvas: .zero) else {
            let l = NSTextField(labelWithString: "This Mac has no Metal.")
            l.alignment = .center
            return l
        }
        return c
    }

    func updateNSView(_ v: NSView, context: Context) {
        if let c = v as? PlotCanvas { update(c, context.coordinator) }
    }
}
#endif

// what a tapped item is, as the window's inspector shows it
private struct CardView: View {
    let card: Card
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title).font(.headline)
                Spacer()
                Button { model.act("view-unpick") } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
            }
            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline) {
                    Text(r.k).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                    Text(r.v).textSelection(.enabled).lineLimit(2)
                }
                .font(.subheadline)
            }
            Button("Mention in chat") { model.act("view-mention", card.info) }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)).allowsHitTesting(false))
        .padding(12)
    }
}

// under the viewer's bar: the schematic's sheet, the layers shown (only
// those this board or sheet has), and the 3D model's parts
struct ViewerControls: View {
    let model: AppModel
    let viewer: Viewer
    let present: Set<Int>

    var body: some View {
        let sheets = viewer.sheets ?? []
        let layers = (viewer.layerList ?? []).filter { present.contains($0.layer) }
        // nothing to offer, no palette
        if !sheets.isEmpty || !layers.isEmpty || viewer.open == "3d" {
        HStack(spacing: 8) {
            if !sheets.isEmpty {
                Menu {
                    ForEach(sheets, id: \.value) { s in
                        Button { model.act("view-sheet", s.value) } label: {
                            if s.on { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                        }
                        .disabled(s.loop)
                    }
                } label: {
                    Label(sheets.first { $0.on }?.label.trimmingCharacters(in: .whitespaces) ?? "Sheet", systemImage: "doc.on.doc")
                }
                .plainMenu()
            }
            if !layers.isEmpty {
                // stays open: several layers are turned on and off in a row
                Menu {
                    ForEach(layers, id: \.layer) { l in
                        Button { model.act("view-layer", String(l.layer)) } label: {
                            Label(l.name, systemImage: l.on ? "checkmark.square" : "square")
                        }
                    }
                } label: {
                    Label("Layers", systemImage: "square.3.layers.3d")
                }
                .plainMenu()
                .keepsMenuOpen()
            }
            if viewer.open == "3d" {
                Toggle(isOn: Binding(get: { viewer.parts ?? true }, set: { _ in model.act("view-parts") })) { Text("Parts") }
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)).allowsHitTesting(false))
        }
    }
}

// The viewer over the thread: the plot of the screen's source, the source
// choices, the card of what was tapped, and a way back.
struct PlotScreen: View {
    let model: AppModel
    let viewer: Viewer

    var body: some View {
        // a plot for any other source is stale (a switch in flight)
        let f = model.plots.frame.flatMap { $0.key == viewer.layers ? $0 : nil }
        let m = model.plots.mesh.flatMap { $0.key == viewer.key ? $0 : nil }
        VStack(spacing: 0) {
            // the viewer's own bar: what it shows, its ground, and a way out
            HStack(spacing: 10) {
                Picker("Source", selection: Binding(get: { viewer.open }, set: { model.act("view", $0) })) {
                    ForEach(viewer.choices, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                // the viewer's own light or dark ground
                Button { model.act("vw-light") } label: { Image(systemName: viewer.light == true ? "moon" : "sun.max") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(viewer.light == true ? "Dark ground" : "Light ground")
                Button { model.act("view", "") } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.bar)
            ZStack {
                Color(rgb: viewer.bg)
                PlotCanvasView(frame: f?.none.isEmpty == true ? f : nil, mesh: m, viewer: viewer) { model.act("view-pick", $0) }
                if f == nil {
                    ProgressView().tint(.white)
                } else if let why = f?.none, !why.isEmpty {
                    Text(why).foregroundStyle(.secondary)
                } else if viewer.open == "3d", let why = m?.none, !why.isEmpty {
                    Text(why).font(.caption).foregroundStyle(.secondary).padding().frame(maxHeight: .infinity, alignment: .bottom)
                } else if viewer.open == "3d", viewer.parts ?? true, let note = viewer.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).padding().frame(maxHeight: .infinity, alignment: .bottom)
                }
                // sheet, layers and parts float over the canvas, top right
                ViewerControls(model: model, viewer: viewer, present: Set(f?.chunks.map { $0.layer } ?? []))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                if let c = viewer.card {
                    CardView(card: c, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .viewerScheme(viewer.light == true ? .light : .dark)
        .hiddenStatusBar()
    }
}

extension View {
    // the board viewer: over the thread on a phone, in a pane beside the
    // thread on a Mac
    func boardViewer(model: AppModel, open: Bool) -> some View {
        modifier(BoardViewer(model: model, open: open))
    }
}

private struct BoardViewer: ViewModifier {
    let model: AppModel
    let open: Bool
    @Environment(\.splitLayout) private var split
    // the board's share of the space, set by dragging the divider
    @State private var share: CGFloat = 0.5

    func body(content: Content) -> some View {
        if split {
            GeometryReader { g in
                // beside the thread when there is width for both, above it when not
                let wide = g.size.width >= 900
                let total = wide ? g.size.width : g.size.height
                let keep: CGFloat = wide ? 340 : 240, least: CGFloat = wide ? 320 : 220
                let board = max(least, min(total - keep, total * share))
                let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                let viewer = open ? model.screen?.thread?.viewer : nil
                layout {
                    if !wide, let v = viewer {
                        PlotScreen(model: model, viewer: v).frame(height: board)
                        divider(wide: false, total: total)
                    }
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide, let v = viewer {
                        divider(wide: true, total: total)
                        PlotScreen(model: model, viewer: v).frame(width: board)
                    }
                }
            }
            .coordinateSpace(name: "boardSplit")
        } else {
            #if os(iOS)
            content.fullScreenCover(isPresented: Binding(get: { open }, set: { if !$0 { model.act("view", "") } })) {
                if let v = model.screen?.thread?.viewer { PlotScreen(model: model, viewer: v) }
            }
            #else
            content
            #endif
        }
    }

    // a hairline with a wider grip: dragging it moves the split
    private func divider(wide: Bool, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: wide ? 1 : nil, height: wide ? nil : 1)
            .overlay(
                Color.clear
                    .frame(width: wide ? 9 : nil, height: wide ? nil : 9)
                    .contentShape(.rect)
                    .resizeCursor(horizontal: wide)
                    .gesture(DragGesture(coordinateSpace: .named("boardSplit")).onChanged { d in
                        let at = wide ? d.location.x : d.location.y
                        share = min(max(wide ? (total - at) / total : at / total, 0.2), 0.8)
                    })
            )
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
