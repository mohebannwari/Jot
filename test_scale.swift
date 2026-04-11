import Foundation

let containerWidth: Double = 1000
let a4Ratio: Double = 1 / 1.41421356

let containerHeight = containerWidth / a4Ratio
let qlMargin: Double = 40

let availableWidth = containerWidth - (qlMargin * 2)
let scale = containerWidth / availableWidth

print("To fill width, scale by: \(scale)")
