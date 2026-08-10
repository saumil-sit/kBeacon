//
//  Untitled 2.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//


import kbeaconlib2

extension KBeacon: Identifiable {
    public var id: String { self.mac ?? UUID().uuidString }
}
