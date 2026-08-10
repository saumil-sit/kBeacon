//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//


import Foundation

struct KeyValue: Identifiable, Hashable {

    let id = UUID()
    let key: String
    let value: String
}
