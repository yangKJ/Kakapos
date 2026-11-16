//
//  CameraHardwareObservation.swift
//  KakaposMediaCore
//
//  Created by Condy on 2026/11/14.
//

import Foundation

/// 设备属性观测不等于逐帧传感器EXIF；采样点和宿主时刻随值交付。
public struct CameraHardwareObservation: Codable, Equatable, Sendable {
    public enum Point: String, Codable, Sendable { case preview, photoRequest }
    public let point: Point
    public let hostTimeSeconds: Double
    public let iso: Double
    public let minimumISO: Double
    public let exposureSeconds: Double
    public let exposureBiasEV: Double
    public let fNumber: Double
    public let temperatureKelvin: Double
    public let tint: Double
    public let whiteBalanceGains: [Double]
    public let whiteBalanceIsManual: Bool
    public let torchActive: Bool
    public let deviceModelIdentifier: String?
    public let cameraIdentifier: String?
    /// 虚拟多摄当前主实体镜头；不参与设备控制或标定机型键。
    public let primaryCameraIdentifier: String?
    public let zoomFactor: Double?

    public init(
        point: Point,
        hostTimeSeconds: Double,
        iso: Double,
        minimumISO: Double,
        exposureSeconds: Double,
        exposureBiasEV: Double,
        fNumber: Double,
        temperatureKelvin: Double,
        tint: Double,
        whiteBalanceGains: [Double],
        whiteBalanceIsManual: Bool,
        torchActive: Bool,
        deviceModelIdentifier: String? = nil,
        cameraIdentifier: String? = nil,
        zoomFactor: Double? = nil,
        primaryCameraIdentifier: String? = nil
    ) {
        self.point = point
        self.hostTimeSeconds = hostTimeSeconds
        self.iso = iso
        self.minimumISO = minimumISO
        self.exposureSeconds = exposureSeconds
        self.exposureBiasEV = exposureBiasEV
        self.fNumber = fNumber
        self.temperatureKelvin = temperatureKelvin
        self.tint = tint
        self.whiteBalanceGains = whiteBalanceGains
        self.whiteBalanceIsManual = whiteBalanceIsManual
        self.torchActive = torchActive
        self.deviceModelIdentifier = deviceModelIdentifier
        self.cameraIdentifier = cameraIdentifier
        self.zoomFactor = zoomFactor
        self.primaryCameraIdentifier = primaryCameraIdentifier
    }
}
