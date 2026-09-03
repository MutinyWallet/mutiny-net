#!/usr/bin/env python3
import sys
import secrets
from ecdsa import SigningKey, SECP256k1

def generate_keypair():
    # Generate random private key
    private_key = SigningKey.generate(curve=SECP256k1)
    
    # Get private key as hex
    private_hex = private_key.to_string().hex()
    
    # Get public key point
    public_key = private_key.get_verifying_key()
    public_point = public_key.pubkey.point
    
    # Format as compressed public key
    x = public_point.x()
    y = public_point.y()
    
    if y % 2 == 0:
        compressed = f"02{x:064x}"
    else:
        compressed = f"03{x:064x}"
    
    return private_hex, compressed

if __name__ == "__main__":
    try:
        private_hex, public_hex = generate_keypair()
        print(f"PRIVATE:{private_hex}")
        print(f"PUBLIC:{public_hex}")
    except ImportError:
        print("ERROR: ecdsa library not available", file=sys.stderr)
        exit(1)