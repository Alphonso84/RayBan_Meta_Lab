//
//  WearablesConfig.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import MWDATCore

func configureWearables() {
    do {
        try Wearables.configure()
    } catch {
        assertionFailure("Failed to configure Wearables SDK: \(error)")
    }
}
