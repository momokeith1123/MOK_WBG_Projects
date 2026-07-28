# config.py
"""
User-specific configuration for the Risk Sheet Generator.
=========================================================
Fill in YOUR details below. This file is imported by
risk_sheet_generator.py.
"""

import datetime

# ---------------------------------------------------------------------------
# PATHS
# ---------------------------------------------------------------------------

# Folder containing SQL files
SQL_PATH = r"C:\Users\mkeita9\Projects\MOK_WBG_Projects\SQL_Queries\RiskSheet"

# Output folder for Excel files
SAVE_PATH = r"C:\Users\mkeita9\Projects\MOK_WBG_Projects\Python_Scripts\RiskSheet\Output"


# ---------------------------------------------------------------------------
# ORACLE CLIENT
# ---------------------------------------------------------------------------

# Oracle Client installation detected from tnsping
ORACLE_CLIENT_DIR = r"C:\WBG\oracle\product\19.0.0\client_1\bin"


# ---------------------------------------------------------------------------
# DATABASE CREDENTIALS
# ---------------------------------------------------------------------------

# FSMP database
PERF_DB_USER = "mkeita9"
PERF_DB_PASSWORD = "Support_123"
PERF_DB_DSN = "FSMP.worldbank.org"

# ORAMRP1 database
RISK_DB_USER = "MRREAD"
RISK_DB_PASSWORD = "M6r34d#2025"
RISK_DB_DSN = "ORAMRP1.worldbank.org"


# ---------------------------------------------------------------------------
# DATE LOGIC
# ---------------------------------------------------------------------------

# Possible values:
# "DC"
# "SG_LONDON"
# "MANUAL"

OFFICE_LOCATION = "MANUAL"

MANUAL_DATE = datetime.date(2026, 7, 24)