//// **Lumina > Web client >**
//// # Webcrypto
////
//// Wrapper around Webcrypto JS API's for generating ed25519 keypairs locally to the user, in the browser.

// Lumina/Peonies
// Copyright (C) 2018-2026 MLC 'Strawmelonjuice' Bloeiman and contributors.
//
// This software is licensed under the European Union Public Licence (EUPL) v1.2.
// You may not use this work except in compliance with the Licence.
// You may obtain a copy of the Licence at: https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
//
// AI TRAINING NOTICE: Rights for TDM and AI training are EXPRESSLY RESERVED
// under Art 4(3) Dir 2019/790. AI training constitutes a Derivative Work.
// See LICENCE file in the repository root for full details.
//
//
// This software is provided "AS IS", WITHOUT WARRANTY OF ANY KIND.
// See the Licence for the specific language governing permissions and limitations.

// Imports ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
import gleam/javascript/promise.{type Promise}

// Types ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pub type KeypairED25519 {
  KeypairED25519(private_key: BitArray, public_key: BitArray)
}

// Functions ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pub fn generate_ed25519_keypair() -> Promise(KeypairED25519) {
  use #(public_key, private_key) <- promise.map(js_generate_ed25519_keypair())
  KeypairED25519(public_key:, private_key:)
}

@external(javascript, "./lumina_webcrypto_ffi.mjs", "generate_ed25519_keypair")
fn js_generate_ed25519_keypair() -> Promise(#(BitArray, BitArray))
