# src/ — Core Application Modules

---

## File: `src/__init__.py`

```python
# src/__init__.py
# Makes src a package.
```

---

## File: `src/formatter.py`

```python
# src/formatter.py
# ─────────────────────────────────────────────────────────────────────────────
# Number formatting helpers for the LAM Daily Report.
# All report values are displayed in USD thousands with parenthetical negatives.
# ─────────────────────────────────────────────────────────────────────────────

import math


def fmt(value, in_thousands: bool = True) -> str:
    """
    Format a numeric value for display in the report.

    Rules:
      - Divides by 1,000 when in_thousands=True (default)
      - Returns ' - '  for zero values
      - Returns '#N/A' for None or NaN
      - Negative values wrapped in parentheses: (1,234.56)
      - Positive values with leading space:      1,234.56

    Args:
        value:        The raw numeric value from the database.
        in_thousands: If True, divide by 1,000 before formatting.

    Returns:
        Formatted string ready for the PDF cell.
    """
    if value is None:
        return "#N/A"
    if isinstance(value, float) and math.isnan(value):
        return "#N/A"

    v = value / 1_000 if in_thousands else value

    if v == 0:
        return " - "
    if v < 0:
        return f"({abs(v):,.2f})"
    return f" {v:,.2f} "


def is_negative(text: str) -> bool:
    """
    Return True if a formatted string represents a negative number.
    Used to apply red colour to negative cells in the PDF.

    Args:
        text: A formatted string from fmt().

    Returns:
        True if the value is wrapped in parentheses.
    """
    return isinstance(text, str) and text.strip().startswith("(")


def safe_sum(series) -> float:
    """
    Return the sum of a pandas Series as a float.
    Returns 0.0 if the Series is empty.

    Args:
        series: A pandas Series of numeric values.

    Returns:
        Float sum, or 0.0 if empty.
    """
    return float(series.sum()) if not series.empty else 0.0
```

---

## File: `src/db.py`

```python
# src/db.py
# ─────────────────────────────────────────────────────────────────────────────
# FDL database connection and data retrieval for the LAM Daily Report.
# ─────────────────────────────────────────────────────────────────────────────

import logging

import pandas as pd
import pyodbc

logger = logging.getLogger("lam_report")

SQL_QUERY = """
SELECT
    Business_Date,
    Portfolio_Level_1,
    Portfolio_Level_2,
    Portfolio_Level_3,
    Portfolio_Level_4,
    Deal_Type,
    Fiscal_Year_Start_Date,
    Fiscal_Year_End_Date,
    SUM(Market_Value)     AS MV,
    SUM(Market_Value_USD) AS MV_USD,
    SUM(Cash)             AS Cash,
    SUM(Cash_USD)         AS Cash_USD,
    SUM(NAV)              AS NAV,
    SUM(NAV_USD)          AS NAV_USD,
    SUM(DTD_PnL)          AS DTD_PnL,
    SUM(DTD_PnL_USD)      AS DTD_PnL_USD,
    SUM(MTD_PnL)          AS MTD_PnL,
    SUM(MTD_PnL_USD)      AS MTD_PnL_USD,
    SUM(YTD_PnL)          AS YTD_PnL,
    SUM(YTD_PnL_USD)      AS YTD_PnL_USD
FROM publishFINDATAREP.IFCTRE.Operational_Data.UserReport.LAM_SubAccount_Summary
GROUP BY
    Business_Date,
    Portfolio_Level_1,
    Portfolio_Level_2,
    Portfolio_Level_3,
    Portfolio_Level_4,
    Deal_Type,
    Fiscal_Year_Start_Date,
    Fiscal_Year_End_Date
"""


def fetch_data(connection_string: str) -> pd.DataFrame:
    """
    Connect to FDL and retrieve the LAM Sub-Account Summary for the latest
    available business date.

    Args:
        connection_string: ODBC connection string from config/settings.py.

    Returns:
        DataFrame filtered to the latest Business_Date only.

    Raises:
        pyodbc.Error: If the connection or query fails.
        ValueError:   If the query returns no rows.
    """
    logger.info("Connecting to FDL...")
    conn   = pyodbc.connect(connection_string)
    df_all = pd.read_sql(SQL_QUERY, conn)
    conn.close()

    if df_all.empty:
        raise ValueError("Query returned no rows. Check FDL table and permissions.")

    latest_date = df_all["Business_Date"].max()
    df          = df_all[df_all["Business_Date"] == latest_date].copy()

    logger.info(f"Data fetched — Business Date: {latest_date} | Rows: {len(df)}")
    logger.debug(f"Deal_Type values found: {df['Deal_Type'].unique().tolist()}")
    logger.debug(f"Portfolio_Level_1 values: {df['Portfolio_Level_1'].unique().tolist()}")

    return df
```

---

## File: `src/builder.py`

```python
# src/builder.py
# ─────────────────────────────────────────────────────────────────────────────
# Transforms raw FDL data into an ordered list of display rows for the PDF.
#
# Row types:
#   book_header  → Blue section header (Market Funded / Net Worth)
#   portfolio    → Main portfolio row  (SP USA, GRE, Pool ALM BRL, …)
#   sub          → Sub-row            (Benchmark / Relative / FTP)
#   desk_total   → Desk-level total
#   grand_total  → Book-level grand total
#   blank        → Spacer between sections
# ─────────────────────────────────────────────────────────────────────────────

import logging

import pandas as pd

from src.formatter import fmt, safe_sum

logger = logging.getLogger("lam_report")


def _row(rtype: str, book: str = "", desk: str = "", portfolio: str = "",
         mv: str = "", daily: str = "", mtd: str = "", ytd: str = "") -> dict:
    """Create a standardised display-row dictionary."""
    return dict(type=rtype, book=book, desk=desk, portfolio=portfolio,
                mv=mv, daily=daily, mtd=mtd, ytd=ytd)


def build_rows(df: pd.DataFrame,
               book_order: list,
               db_deal_types: set) -> tuple[str, list]:
    """
    Build the ordered list of display rows from the raw DataFrame.

    The hierarchy follows the management template:
      Book (Portfolio_Level_1)
        └── Desk (Portfolio_Level_2)
              └── Portfolio (Portfolio_Level_3)
                    ├── Benchmark  (from DB, Deal_Type = "Benchmark")
                    ├── Relative   (computed: Portfolio P&L − Benchmark P&L)
                    └── FTP        (from DB, Deal_Type = "FTP")

    Args:
        df:            DataFrame from db.fetch_data().
        book_order:    List of Portfolio_Level_1 values in display order.
        db_deal_types: Set of Deal_Type values stored in DB (not computed).

    Returns:
        Tuple of (report_date_string, list_of_row_dicts).
    """
    latest_date = pd.to_datetime(df["Business_Date"].max())

    # Date format: Linux/Mac uses %-m, Windows uses %#m
    try:
        report_date = latest_date.strftime("%-m/%-d/%Y")
    except ValueError:
        report_date = latest_date.strftime("%#m/%#d/%Y")   # Windows fallback

    rows = []

    for book in book_order:
        book_df = df[df["Portfolio_Level_1"] == book]
        if book_df.empty:
            logger.warning(f"No data for Book: '{book}' — skipping section.")
            continue

        rows.append(_row("book_header", book=book))
        desks = book_df["Portfolio_Level_2"].dropna().unique()

        for desk in desks:
            desk_df    = book_df[book_df["Portfolio_Level_2"] == desk]
            portfolios = desk_df["Portfolio_Level_3"].dropna().unique()

            for portfolio in portfolios:
                port_df  = desk_df[desk_df["Portfolio_Level_3"] == portfolio]
                main_df  = port_df[~port_df["Deal_Type"].isin(db_deal_types)]
                bm_df    = port_df[port_df["Deal_Type"] == "Benchmark"]
                ftp_df   = port_df[port_df["Deal_Type"] == "FTP"]

                # ── Main portfolio row ────────────────────────────────────────
                mv_val    = safe_sum(main_df["MV_USD"])
                daily_val = safe_sum(main_df["DTD_PnL_USD"])
                mtd_val   = safe_sum(main_df["MTD_PnL_USD"])
                ytd_val   = safe_sum(main_df["YTD_PnL_USD"])

                rows.append(_row("portfolio", desk=desk, portfolio=portfolio,
                                 mv=fmt(mv_val), daily=fmt(daily_val),
                                 mtd=fmt(mtd_val), ytd=fmt(ytd_val)))

                # ── Benchmark sub-row ─────────────────────────────────────────
                bm_daily = safe_sum(bm_df["DTD_PnL_USD"])
                bm_mtd   = safe_sum(bm_df["MTD_PnL_USD"])
                bm_ytd   = safe_sum(bm_df["YTD_PnL_USD"])

                rows.append(_row("sub", portfolio="Benchmark", mv=" - ",
                                 daily=fmt(bm_daily) if not bm_df.empty else " - ",
                                 mtd=fmt(bm_mtd)     if not bm_df.empty else " - ",
                                 ytd=fmt(bm_ytd)     if not bm_df.empty else " - "))

                # ── Relative sub-row (computed) ───────────────────────────────
                rows.append(_row("sub", portfolio="Relative", mv="",
                                 daily=fmt(daily_val - bm_daily),
                                 mtd=fmt(mtd_val   - bm_mtd),
                                 ytd=fmt(ytd_val   - bm_ytd)))

                # ── FTP sub-row ───────────────────────────────────────────────
                if not ftp_df.empty:
                    rows.append(_row("sub", portfolio="FTP",
                                     mv=fmt(safe_sum(ftp_df["MV_USD"])),
                                     daily=fmt(safe_sum(ftp_df["DTD_PnL_USD"])),
                                     mtd=fmt(safe_sum(ftp_df["MTD_PnL_USD"])),
                                     ytd=fmt(safe_sum(ftp_df["YTD_PnL_USD"]))))
                else:
                    rows.append(_row("sub", portfolio="FTP",
                                     mv="#N/A", daily="#N/A",
                                     mtd="#N/A", ytd="#N/A"))

            # ── Desk total ────────────────────────────────────────────────────
            d_main = desk_df[~desk_df["Deal_Type"].isin(db_deal_types)]
            d_ftp  = desk_df[desk_df["Deal_Type"] == "FTP"]

            rows.append(_row("desk_total", desk="Total",
                             mv=fmt(safe_sum(d_main["MV_USD"])),
                             daily=fmt(safe_sum(d_main["DTD_PnL_USD"])),
                             mtd=fmt(safe_sum(d_main["MTD_PnL_USD"])),
                             ytd=fmt(safe_sum(d_main["YTD_PnL_USD"]))))
            rows.append(_row("sub", portfolio="Benchmark",
                             mv=" - ", daily=" - ", mtd=" - ", ytd=" - "))
            rows.append(_row("sub", portfolio="Relative", mv="",
                             daily=fmt(safe_sum(d_main["DTD_PnL_USD"])),
                             mtd=fmt(safe_sum(d_main["MTD_PnL_USD"])),
                             ytd=fmt(safe_sum(d_main["YTD_PnL_USD"]))))
            rows.append(_row("sub", portfolio="FTP",
                             mv=fmt(safe_sum(d_ftp["MV_USD"])),
                             daily=fmt(safe_sum(d_ftp["DTD_PnL_USD"])),
                             mtd=fmt(safe_sum(d_ftp["MTD_PnL_USD"])),
                             ytd=fmt(safe_sum(d_ftp["YTD_PnL_USD"]))))

        # ── Book grand total ──────────────────────────────────────────────────
        b_main = book_df[~book_df["Deal_Type"].isin(db_deal_types)]
        rows.append(_row("grand_total", book="Total",
                         mv=fmt(safe_sum(b_main["MV_USD"])),
                         daily=fmt(safe_sum(b_main["DTD_PnL_USD"])),
                         mtd=fmt(safe_sum(b_main["MTD_PnL_USD"])),
                         ytd=fmt(safe_sum(b_main["YTD_PnL_USD"]))))
        rows.append(_row("blank"))

    logger.info(f"Report rows built: {len(rows)} total")
    return report_date, rows
```

---

## File: `src/pdf_generator.py`

```python
# src/pdf_generator.py
# ─────────────────────────────────────────────────────────────────────────────
# ReportLab PDF generation for the LAM Daily Confidential Report.
# Produces a landscape A3 document matching the management template.
# ─────────────────────────────────────────────────────────────────────────────

import logging
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from src.formatter import is_negative

logger = logging.getLogger("lam_report")

# ── Colour palette ────────────────────────────────────────────────────────────
DARK_BLUE  = colors.HexColor("#1F3864")
MED_BLUE   = colors.HexColor("#2E5EAA")
LIGHT_BLUE = colors.HexColor("#D6E4F0")
LIGHT_GRAY = colors.HexColor("#F5F5F5")
RED        = colors.HexColor("#C00000")
GRAY_TEXT  = colors.HexColor("#555555")

# ── Column widths (landscape A3 usable width ≈ 16.1 in) ──────────────────────
COL_WIDTHS = [1.0*inch, 2.1*inch, 2.5*inch, 2.5*inch, 2.5*inch, 2.5*inch, 2.5*inch]


def _para(text: str, align: str = "RIGHT", bold: bool = False,
          color=colors.black, size: int = 8) -> Paragraph:
    """Create a styled ReportLab Paragraph for a table cell."""
    style = ParagraphStyle(
        "cell",
        fontName="Helvetica-Bold" if bold else "Helvetica",
        fontSize=size,
        textColor=color,
        alignment={"RIGHT": TA_RIGHT, "LEFT": TA_LEFT, "CENTER": TA_CENTER}[align],
        leading=size + 2,
    )
    return Paragraph(str(text), style)


def _num(text: str, bold: bool = False, size: int = 8) -> Paragraph:
    """Right-aligned number cell — red if negative."""
    c = RED if is_negative(text) else colors.black
    return _para(text, align="RIGHT", bold=bold, color=c, size=size)


def generate_pdf(report_date: str, rows: list, output_path: str) -> None:
    """
    Generate the LAM Daily Confidential PDF report.

    Args:
        report_date: Formatted date string (e.g. "8/24/2026").
        rows:        Ordered list of display-row dicts from builder.build_rows().
        output_path: Full file path where the PDF will be saved.
    """
    logger.info(f"Generating PDF: {output_path}")

    doc   = SimpleDocTemplate(output_path, pagesize=landscape(A3),
                               leftMargin=0.4*inch, rightMargin=0.4*inch,
                               topMargin=0.5*inch,  bottomMargin=0.4*inch)
    story = []

    # ── Title block ───────────────────────────────────────────────────────────
    story.append(_para("IFC Treasury — LAM Sub-Account Summary",
                        align="LEFT", bold=True, color=DARK_BLUE, size=13))
    story.append(_para(f"Business Date: {report_date}",
                        align="LEFT", color=GRAY_TEXT, size=9))
    story.append(_para("CONFIDENTIAL — For Internal Management Distribution Only",
                        align="RIGHT", bold=True, color=RED, size=9))
    story.append(Spacer(1, 0.12 * inch))

    # ── Table headers ─────────────────────────────────────────────────────────
    hdr1 = [
        _para(report_date,       "LEFT",   bold=True, color=colors.white, size=8),
        _para("Desk",            "LEFT",   bold=True, color=colors.white, size=8),
        _para("Portfolio",       "LEFT",   bold=True, color=colors.white, size=8),
        _para("Market Value (USD)", "CENTER", bold=True, color=colors.white, size=8),
        _para("P&L",             "CENTER", bold=True, color=colors.white, size=8),
        _para("",                "CENTER", bold=True, color=colors.white, size=8),
        _para("",                "CENTER", bold=True, color=colors.white, size=8),
    ]
    hdr2 = [
        _para("Book",            "LEFT",  bold=True, color=colors.white, size=8),
        _para("",                "LEFT",  bold=True, color=colors.white, size=8),
        _para("",                "LEFT",  bold=True, color=colors.white, size=8),
        _para("MV (000's)",      "RIGHT", bold=True, color=colors.white, size=8),
        _para("Daily (000's)",   "RIGHT", bold=True, color=colors.white, size=8),
        _para("MTD (000's)",     "RIGHT", bold=True, color=colors.white, size=8),
        _para("YTD (000's)",     "RIGHT", bold=True, color=colors.white, size=8),
    ]

    table_data = [hdr1, hdr2]
    style_cmds = [
        ("BACKGROUND",    (0, 0), (-1, 1), DARK_BLUE),
        ("SPAN",          (4, 0), (6, 0)),
        ("GRID",          (0, 0), (-1, -1), 0.3, colors.HexColor("#CCCCCC")),
        ("LINEBELOW",     (0, 1), (-1, 1),  1.0, colors.white),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING",    (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING",   (0, 0), (-1, -1), 4),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 4),
    ]

    ri  = 2
    alt = False

    for r in rows:
        rtype = r["type"]

        if rtype == "blank":
            table_data.append([_para("") for _ in range(7)])
            style_cmds.append(("ROWHEIGHT", (0, ri), (-1, ri), 5))

        elif rtype == "book_header":
            table_data.append([
                _para(r["book"], "LEFT", bold=True, color=colors.white, size=9),
                *[_para("") for _ in range(6)],
            ])
            style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), MED_BLUE))
            alt = False

        elif rtype == "grand_total":
            table_data.append([
                _para("Total", "LEFT", bold=True, size=8),
                _para(""), _para(""),
                _num(r["mv"],    bold=True, size=8),
                _num(r["daily"], bold=True, size=8),
                _num(r["mtd"],   bold=True, size=8),
                _num(r["ytd"],   bold=True, size=8),
            ])
            style_cmds += [
                ("BACKGROUND", (0, ri), (-1, ri), LIGHT_BLUE),
                ("LINEABOVE",  (0, ri), (-1, ri), 0.8, DARK_BLUE),
            ]

        elif rtype == "desk_total":
            table_data.append([
                _para(""),
                _para("Total", "LEFT", bold=True, size=8), _para(""),
                _num(r["mv"],    bold=True, size=8),
                _num(r["daily"], bold=True, size=8),
                _num(r["mtd"],   bold=True, size=8),
                _num(r["ytd"],   bold=True, size=8),
            ])
            style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), LIGHT_BLUE))

        elif rtype == "portfolio":
            bg = LIGHT_GRAY if alt else colors.white
            alt = not alt
            table_data.append([
                _para(""),
                _para(r["desk"],      "LEFT", bold=True,  size=8),
                _para(r["portfolio"], "LEFT", bold=False, size=8),
                _num(r["mv"],    size=8),
                _num(r["daily"], size=8),
                _num(r["mtd"],   size=8),
                _num(r["ytd"],   size=8),
            ])
            style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), bg))

        elif rtype == "sub":
            lbl  = r["portfolio"]
            bold = lbl == "Relative"
            table_data.append([
                _para(""), _para(""),
                _para(f"      {lbl}", "LEFT", bold=bold, color=GRAY_TEXT, size=7),
                _para(r["mv"],    "RIGHT", bold=bold,
                      color=RED if is_negative(r["mv"])    else GRAY_TEXT, size=7),
                _para(r["daily"], "RIGHT", bold=bold,
                      color=RED if is_negative(r["daily"]) else GRAY_TEXT, size=7),
                _para(r["mtd"],   "RIGHT", bold=bold,
                      color=RED if is_negative(r["mtd"])   else GRAY_TEXT, size=7),
                _para(r["ytd"],   "RIGHT", bold=bold,
                      color=RED if is_negative(r["ytd"])   else GRAY_TEXT, size=7),
            ])

        ri += 1

    table = Table(table_data, colWidths=COL_WIDTHS, repeatRows=2)
    table.setStyle(TableStyle(style_cmds))
    story.append(table)
    story.append(Spacer(1, 0.12 * inch))
    story.append(_para(
        f"Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}  |  "
        "IFC Treasury Operations  |  CONFIDENTIAL",
        align="CENTER", color=GRAY_TEXT, size=7,
    ))

    doc.build(story)
    logger.info("PDF generation complete.")
```

---

*This document was generated by mAI.*
