# tests/ — Unit Tests and Sample Data

---

## File: `tests/test_formatter.py`

```python
# tests/test_formatter.py
# ─────────────────────────────────────────────────────────────────────────────
# Unit tests for src/formatter.py
# Run with: python -m pytest tests/test_formatter.py -v
# No FDL connection required.
# ─────────────────────────────────────────────────────────────────────────────

import pytest
from src.formatter import fmt, is_negative, safe_sum
import pandas as pd


class TestFmt:
    def test_positive_value(self):
        assert fmt(1_234_567.89) == " 1,234.57 "

    def test_negative_value(self):
        assert fmt(-1_234_567.89) == "(1,234.57)"

    def test_zero(self):
        assert fmt(0) == " - "

    def test_none(self):
        assert fmt(None) == "#N/A"

    def test_nan(self):
        assert fmt(float("nan")) == "#N/A"

    def test_no_thousands_division(self):
        assert fmt(1_234.56, in_thousands=False) == " 1,234.56 "

    def test_small_positive(self):
        assert fmt(500) == " 0.50 "

    def test_small_negative(self):
        assert fmt(-500) == "(0.50)"


class TestIsNegative:
    def test_negative_string(self):
        assert is_negative("(1,234.56)") is True

    def test_positive_string(self):
        assert is_negative(" 1,234.56 ") is False

    def test_dash(self):
        assert is_negative(" - ") is False

    def test_na(self):
        assert is_negative("#N/A") is False

    def test_empty(self):
        assert is_negative("") is False

    def test_non_string(self):
        assert is_negative(None) is False


class TestSafeSum:
    def test_normal_series(self):
        s = pd.Series([100.0, 200.0, 300.0])
        assert safe_sum(s) == 600.0

    def test_empty_series(self):
        s = pd.Series([], dtype=float)
        assert safe_sum(s) == 0.0

    def test_negative_series(self):
        s = pd.Series([-100.0, 50.0])
        assert safe_sum(s) == -50.0
```

---

## File: `tests/test_builder.py`

```python
# tests/test_builder.py
# ─────────────────────────────────────────────────────────────────────────────
# Unit tests for src/builder.py
# Run with: python -m pytest tests/test_builder.py -v
# Uses tests/sample_data.csv — no FDL connection required.
# ─────────────────────────────────────────────────────────────────────────────

import os
import pytest
import pandas as pd
from src.builder import build_rows

SAMPLE_CSV = os.path.join(os.path.dirname(__file__), "sample_data.csv")
BOOK_ORDER    = ["Market Funded", "Net Worth"]
DB_DEAL_TYPES = {"Benchmark", "FTP"}


@pytest.fixture
def sample_df():
    """Load the sample CSV dataset for offline testing."""
    df = pd.read_csv(SAMPLE_CSV, parse_dates=["Business_Date"])
    return df


class TestBuildRows:
    def test_returns_tuple(self, sample_df):
        result = build_rows(sample_df, BOOK_ORDER, DB_DEAL_TYPES)
        assert isinstance(result, tuple)
        assert len(result) == 2

    def test_report_date_format(self, sample_df):
        report_date, _ = build_rows(sample_df, BOOK_ORDER, DB_DEAL_TYPES)
        # Should match M/D/YYYY format (no leading zeros)
        parts = report_date.split("/")
        assert len(parts) == 3
        assert len(parts[2]) == 4   # year is 4 digits

    def test_rows_is_list(self, sample_df):
        _, rows = build_rows(sample_df, BOOK_ORDER, DB_DEAL_TYPES)
        assert isinstance(rows, list)
        assert len(rows) > 0

    def test_all_row_types_present(self, sample_df):
        _, rows = build_rows(sample_df, BOOK_ORDER, DB_DEAL_TYPES)
        row_types = {r["type"] for r in rows}
        assert "book_header"  in row_types
        assert "portfolio"    in row_types
        assert "sub"          in row_types
        assert "desk_total"   in row_types
        assert "grand_total"  in row_types
        assert "blank"        in row_types

    def test_sub_rows_follow_portfolio(self, sample_df):
        _, rows = build_rows(sample_df, BOOK_ORDER, DB_DEAL_TYPES)
        for i, r in enumerate(rows):
            if r["type"] == "portfolio":
                # Next 3 rows must be Benchmark, Relative, FTP sub-rows
                assert rows[i+1]["type"] == "sub"
                assert rows[i+1]["portfolio"] == "Benchmark"
                assert rows[i+2]["type"] == "sub"
                assert rows[i+2]["portfolio"] == "Relative"
                assert rows[i+3]["type"] == "sub"
                assert rows[i+3]["portfolio"] == "FTP"

    def test_missing_book_skipped_gracefully(self):
        """If a book from BOOK_ORDER has no data, it should be skipped."""
        empty_df = pd.DataFrame(columns=[
            "Business_Date", "Portfolio_Level_1", "Portfolio_Level_2",
            "Portfolio_Level_3", "Portfolio_Level_4", "Deal_Type",
            "MV_USD", "DTD_PnL_USD", "MTD_PnL_USD", "YTD_PnL_USD"
        ])
        # Should not raise, just return empty rows
        report_date, rows = build_rows(empty_df, BOOK_ORDER, DB_DEAL_TYPES)
        assert rows == []
```

---

## File: `tests/sample_data.csv`

This is a **minimal mock dataset** for offline testing. Replace the placeholder values
with a small anonymized extract from your actual FDL data once you have confirmed
the column names and Deal_Type values match.

```csv
Business_Date,Portfolio_Level_1,Portfolio_Level_2,Portfolio_Level_3,Portfolio_Level_4,Deal_Type,MV,MV_USD,Cash,Cash_USD,NAV,NAV_USD,DTD_PnL,DTD_PnL_USD,MTD_PnL,MTD_PnL_USD,YTD_PnL,YTD_PnL_USD,Fiscal_Year_Start_Date,Fiscal_Year_End_Date
2026-08-24,Market Funded,LAM Strategic,SP USA,,Portfolio,4500000000,4500000000,0,0,0,0,-11213050,-11213050,4778918230,4778918230,4778918230,4778918230,2026-07-01,2027-06-30
2026-08-24,Market Funded,LAM Strategic,SP USA,,Benchmark,0,0,0,0,0,0,0,0,0,0,0,0,2026-07-01,2027-06-30
2026-08-24,Market Funded,LAM Strategic,SP USA,,FTP,-9298469650,-9298469650,0,0,0,0,-2911260,-2911260,-3160160,-3160160,-3160160,-3160160,2026-07-01,2027-06-30
2026-08-24,Market Funded,LAM Strategic,GRE,,Portfolio,4232624230,4232624230,0,0,0,0,3277910,3277910,4232217650,4232217650,4232217650,4232217650,2026-07-01,2027-06-30
2026-08-24,Market Funded,LAM Strategic,GRE,,Benchmark,0,0,0,0,0,0,0,0,0,0,0,0,2026-07-01,2027-06-30
2026-08-24,Market Funded,LAM Strategic,GRE,,FTP,-2237894220,-2237894220,0,0,0,0,-700190,-700190,-760050,-760050,-760050,-760050,2026-07-01,2027-06-30
2026-08-24,Net Worth,LAM,UST Tracker,,Portfolio,17913363010,17913363010,0,0,0,0,4550580,4550580,17972231760,17972231760,17972231760,17972231760,2026-07-01,2027-06-30
2026-08-24,Net Worth,LAM,UST Tracker,,Benchmark,0,0,0,0,0,0,0,0,0,0,0,0,2026-07-01,2027-06-30
```

> **Important:** The values in the CSV are in raw units (not thousands) — the `fmt()` function handles the division by 1,000 at display time.

---

*This document was generated by mAI.*
