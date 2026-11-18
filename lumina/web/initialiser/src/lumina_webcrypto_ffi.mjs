import { BitArray$BitArray } from "./gleam.mjs";

export async function generate_ed25519_keypair() {
	const keyPair = await window.crypto.subtle.generateKey(
		{ name: "Ed25519" },
		true,
		["sign", "verify"],
	);

	const pubRaw = await window.crypto.subtle.exportKey(
		"raw",
		keyPair.publicKey,
	);

	const privPkcs8 = await window.crypto.subtle.exportKey(
		"pkcs8",
		keyPair.privateKey,
	);
	const privRaw = privPkcs8.slice(-32);

	const pubBitArray = BitArray$BitArray(new Uint8Array(pubRaw));
	const privBitArray = BitArray$BitArray(new Uint8Array(privRaw));

	return [pubBitArray, privBitArray];
}

export async function sign_message(messageBitArray, privateKeyBitArray) {
	const messageUint8 = messageBitArray.buffer;
	const privKeySeed = privateKeyBitArray.buffer;

	const pkcs8Header = new Uint8Array([
		0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65,
		0x70, 0x04, 0x22, 0x04, 0x20,
	]);
	const pkcs8Bytes = new Uint8Array(pkcs8Header.length + privKeySeed.length);
	pkcs8Bytes.set(pkcs8Header);
	pkcs8Bytes.set(privKeySeed, pkcs8Header.length);

	const cryptoKey = await window.crypto.subtle.importKey(
		"pkcs8",
		pkcs8Bytes,
		{ name: "Ed25519" },
		false,
		["sign"],
	);

	const signatureBuffer = await window.crypto.subtle.sign(
		{ name: "Ed25519" },
		cryptoKey,
		messageUint8,
	);

	return BitArray$BitArray(new Uint8Array(signatureBuffer));
}
export async function verify_signature(
	messageBitArray,
	signatureBitArray,
	publicKeyBitArray,
) {
	const messageUint8 = messageBitArray.buffer;
	const signatureUint8 = signatureBitArray.buffer;
	const pubKeyUint8 = publicKeyBitArray.buffer;

	try {
		const cryptoKey = await window.crypto.subtle.importKey(
			"raw",
			pubKeyUint8,
			{ name: "Ed25519" },
			false,
			["verify"],
		);

		return await window.crypto.subtle.verify(
			{ name: "Ed25519" },
			cryptoKey,
			signatureUint8,
			messageUint8,
		);
	} catch (_err) {
		return false;
	}
}
