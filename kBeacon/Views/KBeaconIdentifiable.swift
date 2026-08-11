//
//  Untitled 2.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//


import Foundation
import kbeaconlib2

extension KBeacon: @retroactive Identifiable {
    public var id: String {
        self.mac ?? UUID().uuidString
    }
}
