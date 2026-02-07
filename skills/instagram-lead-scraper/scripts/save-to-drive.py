#!/usr/bin/env python3
"""
Save Instagram leads CSV to Google Drive.
Usage: python3 save-to-drive.py <csv_file> [--folder "Instagram Leads"]
"""

import sys
import subprocess
import json
from datetime import datetime

def save_to_drive(csv_file, folder="Instagram Leads"):
    """Save CSV file to Google Drive using gog CLI."""
    
    # Read CSV content
    with open(csv_file, 'r') as f:
        content = f.read()
    
    # Get today's date for folder structure
    today = datetime.now().strftime("%Y-%m-%d")
    filename = csv_file.split('/')[-1]
    
    # Use gog to save
    result = subprocess.run(
        ['gog', 'drive', 'upload', csv_file, '--folder', f"{folder}/{today}"],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print(f"✓ Saved to Google Drive: {folder}/{today}/{filename}")
        return True
    else:
        print(f"✗ Failed to save: {result.stderr}")
        return False

def append_to_master(csv_file, master_file="instagram-leads-master.csv"):
    """Append new leads to master CSV, deduplicating by Instagram handle."""
    
    import csv
    
    # Read existing master if it exists
    existing_handles = set()
    try:
        with open(master_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                existing_handles.add(row.get('instagram_handle', '').lower())
    except FileNotFoundError:
        pass
    
    # Read new leads
    new_leads = []
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            handle = row.get('instagram_handle', '').lower()
            if handle and handle not in existing_handles:
                new_leads.append(row)
                existing_handles.add(handle)
    
    # Append to master
    if new_leads:
        fieldnames = new_leads[0].keys()
        with open(master_file, 'a', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if f.tell() == 0:  # File is empty
                writer.writeheader()
            writer.writerows(new_leads)
        
        print(f"✓ Appended {len(new_leads)} new leads to {master_file}")
    else:
        print("No new leads to add (all duplicates)")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 save-to-drive.py <csv_file> [--folder FOLDER]")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    folder = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--folder" else "Instagram Leads"
    
    save_to_drive(csv_file, folder)
    append_to_master(csv_file)
