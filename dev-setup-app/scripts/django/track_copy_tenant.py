#!/usr/bin/env python3
"""
track_copy_tenant.py - Wrapper for Django copy_tenant with progress tracking

This script wraps the copy_tenant management command and tracks progress
by monitoring Django query logs and writing status to a JSON file that
the setup scripts can read and display to the user.

Usage:
    python track_copy_tenant.py --cluster stable t2070 --skip-checks

The progress is written to: /tmp/copy_tenant_progress.json
"""
import os
import sys
import json
import time
import subprocess
from datetime import datetime

PROGRESS_FILE = "/tmp/copy_tenant_progress.json"

class ProgressTracker:
    def __init__(self):
        self.start_time = time.time()
        self.phase = "initializing"
        self.tables_copied = 0
        self.current_table = ""
        self.error = None

    def update(self, phase=None, table=None, tables_copied=None, error=None):
        """Update progress file with current status"""
        if phase:
            self.phase = phase
        if table:
            self.current_table = table
        if tables_copied is not None:
            self.tables_copied = tables_copied
        if error:
            self.error = error

        elapsed = int(time.time() - self.start_time)

        progress_data = {
            "phase": self.phase,
            "tables_copied": self.tables_copied,
            "current_table": self.current_table,
            "elapsed_seconds": elapsed,
            "elapsed_minutes": elapsed // 60,
            "error": self.error,
            "timestamp": datetime.now().isoformat()
        }

        try:
            with open(PROGRESS_FILE, 'w') as f:
                json.dump(progress_data, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to write progress file: {e}", file=sys.stderr)

    def monitor_output(self, line):
        """Parse copy_tenant output for progress indicators"""
        line_lower = line.lower()

        # Detect phase changes
        if "gathering tenant information" in line_lower:
            self.update(phase="gathering_info")
        elif "copying data" in line_lower or "downloading" in line_lower:
            self.update(phase="copying_data")
        elif "creating tenant" in line_lower:
            self.update(phase="creating_tenant")
        elif "migrating" in line_lower:
            self.update(phase="migrating_schemas")
        elif "success" in line_lower or "complete" in line_lower:
            self.update(phase="completed")

        # Try to extract table names from output
        if "table" in line_lower or "copying" in line_lower:
            # Increment table count on any copying activity
            self.tables_copied += 1
            self.update(tables_copied=self.tables_copied)

def main():
    """Run copy_tenant and track progress"""
    if len(sys.argv) < 2:
        print("Usage: track_copy_tenant.py <copy_tenant arguments>")
        print("Example: track_copy_tenant.py --cluster stable t2070 --skip-checks")
        sys.exit(1)

    # Initialize progress tracking
    tracker = ProgressTracker()
    tracker.update(phase="starting")

    # Build the Django management command
    manage_py = os.path.join(os.getcwd(), "manage.py")
    if not os.path.exists(manage_py):
        print("Error: manage.py not found in current directory", file=sys.stderr)
        tracker.update(error="manage.py not found")
        sys.exit(1)

    cmd = [sys.executable, manage_py, "copy_tenant"] + sys.argv[1:]

    print(f"🚀 Starting tracked copy_tenant: {' '.join(sys.argv[1:])}")
    print(f"📊 Progress file: {PROGRESS_FILE}")
    print("")

    try:
        # Start the subprocess with real-time output
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )

        # Read and process output line by line
        while True:
            line = process.stdout.readline()
            if not line:
                break

            # Print to console (maintaining original output)
            print(line, end='')
            sys.stdout.flush()

            # Update progress based on output
            tracker.monitor_output(line)

        # Wait for process to complete
        exit_code = process.wait()

        if exit_code == 0:
            tracker.update(phase="completed")
            print(f"\n✅ Copy tenant completed successfully")
        else:
            tracker.update(phase="failed", error=f"Exit code {exit_code}")
            print(f"\n❌ Copy tenant failed with exit code {exit_code}")

        sys.exit(exit_code)

    except Exception as e:
        error_msg = str(e)
        tracker.update(phase="error", error=error_msg)
        print(f"\n❌ Error running copy_tenant: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Clean up progress file after completion
        time.sleep(2)  # Give time for final progress read
        if os.path.exists(PROGRESS_FILE):
            try:
                os.remove(PROGRESS_FILE)
            except:
                pass

if __name__ == "__main__":
    main()
