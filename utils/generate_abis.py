#!/usr/bin/env python3
"""
ABI Generator for Yearn YB Contracts

Generates ABI JSON files for all contracts in src/ directory,
excluding contracts in src/interfaces/ and src/utils/.

Usage:
    python utils/generate_abis.py
"""

import json
import os
import subprocess
from pathlib import Path


def get_contract_files(src_dir: Path) -> list[Path]:
    """Find all .sol files in src/ excluding interfaces and utils."""
    all_files = src_dir.rglob("*.sol")

    # Filter out interfaces and utils directories
    contracts = []
    for file in all_files:
        rel_path = file.relative_to(src_dir)
        if rel_path.parts[0] not in ("interfaces", "utils"):
            contracts.append(file)

    return contracts


def get_contract_name(sol_file: Path) -> str:
    """Extract contract name from .sol filename."""
    return sol_file.stem


def generate_abi(contract_name: str, output_dir: Path) -> bool:
    """Generate ABI for a contract using forge."""
    try:
        # Build the project first (silently)
        subprocess.run(
            ["forge", "build", "--silent"],
            check=True,
            capture_output=True
        )

        # Extract ABI using jq
        artifact_path = f"out/{contract_name}.sol/{contract_name}.json"
        output_path = output_dir / f"{contract_name}.json"

        result = subprocess.run(
            ["jq", ".abi", artifact_path],
            check=True,
            capture_output=True,
            text=True
        )

        # Write ABI to output file
        with open(output_path, "w") as f:
            f.write(result.stdout)

        print(f"✓ Generated ABI for {contract_name}")
        return True

    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to generate ABI for {contract_name}: {e}")
        return False
    except FileNotFoundError as e:
        print(f"✗ Artifact not found for {contract_name}: {e}")
        return False


def main():
    """Main entry point."""
    # Get project root (assuming script is in utils/)
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    src_dir = project_root / "src"
    output_dir = project_root / "abis"

    # Create abis directory if it doesn't exist
    output_dir.mkdir(exist_ok=True)

    print("Generating ABIs for Yearn YB contracts...\n")

    # Find all contract files
    contracts = get_contract_files(src_dir)

    if not contracts:
        print("No contracts found in src/")
        return

    print(f"Found {len(contracts)} contract(s):\n")

    # Generate ABIs
    success_count = 0
    for contract_file in contracts:
        contract_name = get_contract_name(contract_file)
        if generate_abi(contract_name, output_dir):
            success_count += 1

    print(f"\n{success_count}/{len(contracts)} ABIs generated successfully")


if __name__ == "__main__":
    main()
