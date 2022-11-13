/// The contents of this file are more or less literal translations of wlroots's matrix functions.
/// wlroots is released under a MIT license.
/// See https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/master/types/wlr_matrix.c

import Glibc

import DataStructures

func wlr_matrix_identity(_ mat: UnsafeMutablePointer<Float>) {
    let identity: [Float] = [
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    ]
    memcpy(mat, identity, MemoryLayout<Float>.size * 9)
}

func wlr_matrix_multiply(
    _ mat: UnsafeMutablePointer<Float>,
    _ a: UnsafePointer<Float>,
    _ b: UnsafePointer<Float>
) {
    let product: [Float] = [
        a[0]*b[0] + a[1]*b[3] + a[2]*b[6],
        a[0]*b[1] + a[1]*b[4] + a[2]*b[7],
        a[0]*b[2] + a[1]*b[5] + a[2]*b[8],

        a[3]*b[0] + a[4]*b[3] + a[5]*b[6],
        a[3]*b[1] + a[4]*b[4] + a[5]*b[7],
        a[3]*b[2] + a[4]*b[5] + a[5]*b[8],

        a[6]*b[0] + a[7]*b[3] + a[8]*b[6],
        a[6]*b[1] + a[7]*b[4] + a[8]*b[7],
        a[6]*b[2] + a[7]*b[5] + a[8]*b[8]
    ]

    memcpy(mat, product, MemoryLayout<Float>.size * 9)
}

func wlr_matrix_transpose(
    _ mat: UnsafeMutablePointer<Float>,
    _ a: UnsafePointer<Float>
) {
    let transposition: [Float] = [
        a[0], a[3], a[6],
        a[1], a[4], a[7],
        a[2], a[5], a[8],
    ]
    memcpy(mat, transposition, MemoryLayout<Float>.size * 9)
}

func wlr_matrix_translate(_ mat: UnsafeMutablePointer<Float>, _ x: Float, _ y: Float) {
    let translate = [
        1.0, 0.0, x,
        0.0, 1.0, y,
        0.0, 0.0, 1.0,
    ]
    wlr_matrix_multiply(mat, mat, translate)
}

func wlr_matrix_scale(_ mat: UnsafeMutablePointer<Float>, _ x: Float, _ y: Float) {
    let scale: [Float] = [
        x,   0.0, 0.0,
        0.0, y,   0.0,
        0.0, 0.0, 1.0,
    ]
    wlr_matrix_multiply(mat, mat, scale)
}

func wlr_matrix_rotate(_ mat: UnsafeMutablePointer<Float>, _ rad: Float) {
    let rotate: [Float] = [
        cos(rad), -sin(rad), 0.0,
        sin(rad),  cos(rad), 0.0,
        0.0,       0.0,      1.0,
    ]
    wlr_matrix_multiply(mat, mat, rotate)
}

func wlr_matrix_transform(_ mat: UnsafeMutablePointer<Float>, _ transform: wl_output_transform) {
    let t: [Float]
    switch transform {
    case .WL_OUTPUT_TRANSFORM_NORMAL:
        t = [
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        ]
    case .WL_OUTPUT_TRANSFORM_FLIPPED_180:
        t = [
            1.0, 0.0, 0.0,
            0.0, -1.0, 0.0,
            0.0, 0.0, 1.0,
        ]
    }

    wlr_matrix_multiply(mat, mat, t)
}


func wlr_matrix_project_box(
    _ mat: UnsafeMutablePointer<Float>,
    _ box: inout Box,
    _ transform: wl_output_transform,
    _ rotation: Float,
    _ projection: UnsafePointer<Float>
) {
    let x = Float(box.x)
    let y = Float(box.y)
    let width = Float(box.width)
    let height = Float(box.height)

    wlr_matrix_identity(mat)
    wlr_matrix_translate(mat, x, y)

    if rotation != 0 {
        wlr_matrix_translate(mat, width/2, height/2)
        wlr_matrix_rotate(mat, rotation)
        wlr_matrix_translate(mat, -width/2, -height/2)
    }

    wlr_matrix_scale(mat, width, height)

    if transform != .WL_OUTPUT_TRANSFORM_NORMAL {
        wlr_matrix_translate(mat, 0.5, 0.5)
        wlr_matrix_transform(mat, transform)
        wlr_matrix_translate(mat, -0.5, -0.5)
    }

    wlr_matrix_multiply(mat, projection, mat)
}

func wlr_matrix_projection(
    _ mat: UnsafeMutablePointer<Float>,
    _ width: Int32,
    _ height: Int32,
    _ transform: wl_output_transform
) {
    memset(mat, 0, MemoryLayout<Float>.size * 9)

    let t: [Float]
    switch transform {
    case .WL_OUTPUT_TRANSFORM_NORMAL:
        t = [
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        ]
    case .WL_OUTPUT_TRANSFORM_FLIPPED_180:
        t = [
            1.0, 0.0, 0.0,
            0.0, -1.0, 0.0,
            0.0, 0.0, 1.0,
        ]
    }

    let x = 2.0 / Float(width)
    let y = 2.0 / Float(height)

    // Rotation + reflection
    mat[0] = x * t[0]
    mat[1] = x * t[1]
    mat[3] = y * -t[3]
    mat[4] = y * -t[4]

    // Translation
    mat[2] = -copysign(1.0, mat[0] + mat[1])
    mat[5] = -copysign(1.0, mat[3] + mat[4])

    // Identity
    mat[8] = 1.0
}
