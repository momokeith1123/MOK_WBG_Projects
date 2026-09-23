# IFC Treasury — LAM Daily Report | Development Notebook

This notebook is structured in **6 independent cells**. Run them top to bottom.
Each cell has a clear purpose so you can test and validate at each stage before moving on.

---

## Cell 1 — Install & Import Dependencies

```python
# ── Install (run once; comment out after first run) ───────────────────────────
# !pip install pyodbc pandas reportlab

import os
import pyodbc
import pandas as pd
import smtplib
from datetime import datetime
from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

print("✅ All libraries imported successfully.")
```

---

## Cell 2 — Configuration

```python
# ── Database ──────────────────────────────────────────────────────────────────
# Replace the placeholders below with your actual FDL server and credentials.
# For SSO / Active Directory, use Authentication=ActiveDirectoryIntegrated
# and remove UID/PWD lines.

CONNECTION_STRING = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=<your_fdl_server>;"           # ← replace
    "DATABASE=publishFINDATAREP;"
    "Authentication=ActiveDirectoryIntegrated;"
    # "UID=<username>;"                   # ← uncomment if using SQL login
    # "PWD=<password>;"                   # ← uncomment if using SQL login
)

# ── Email ─────────────────────────────────────────────────────────────────────
SMTP_SERVER = "smtp.ifc.org"              # ← replace with your IFC SMTP relay
SMTP_PORT   = 25
FROM_EMAIL  = "treasury-reports@ifc.org" # ← replace
TO_EMAILS   = [
    "recipient-1@ifc.org",               # ← replace with real recipients
    "recipient-2@ifc.org",
]
CC_EMAILS   = []

# ── Output ────────────────────────────────────────────────────────────────────
OUTPUT_DIR = "./output"
os.makedirs(OUTPUT_DIR, exist_ok=True)

print("✅ Configuration loaded.")
print(f"   Output directory: {os.path.abspath(OUTPUT_DIR)}")
```

---

## Cell 3 — Fetch Data from FDL

> **Validation checkpoint:** After running this cell, inspect `df` to confirm
> the row count, the latest business date, and that all expected columns are present.

```python
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

print("Connecting to FDL...")
conn    = pyodbc.connect(CONNECTION_STRING)
df_raw  = pd.read_sql(SQL_QUERY, conn)
conn.close()

# Keep latest business date only
latest_date = df_raw["Business_Date"].max()
df = df_raw[df_raw["Business_Date"] == latest_date].copy()

print(f"✅ Data fetched successfully.")
print(f"   Latest Business Date : {latest_date}")
print(f"   Total rows           : {len(df)}")
print(f"   Columns              : {list(df.columns)}")
print()

# ── Quick inspection ──────────────────────────────────────────────────────────
print("── Portfolio_Level_1 (Book) values ──────────────────────")
print(df["Portfolio_Level_1"].value_counts())
print()
print("── Portfolio_Level_2 (Desk) values ──────────────────────")
print(df["Portfolio_Level_2"].value_counts())
print()
print("── Deal_Type values ─────────────────────────────────────")
print(df["Deal_Type"].value_counts())
print()
print("── Sample rows ──────────────────────────────────────────")
df.head(10)
```

---

## Cell 4 — Build Report Rows

> **Validation checkpoint:** Print `rows` to verify the hierarchy matches the
> template. Check that Relative values are correctly computed (Portfolio P&L − Benchmark P&L).
> If Deal_Type values differ from "Benchmark"/"FTP", update `DB_DEAL_TYPES` below.

```python
# ── Settings — adjust to match your actual Deal_Type values if needed ─────────
BOOK_ORDER    = ["Market Funded", "Net Worth"]   # controls section order
DB_DEAL_TYPES = {"Benchmark", "FTP"}             # deal types stored in DB (not computed)

# ── Helpers ───────────────────────────────────────────────────────────────────
def fmt(value, in_thousands=True):
    """Format number: thousands, parentheses for negatives, dash for zero."""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return "#N/A"
    v = value / 1_000 if in_thousands else value
    if v == 0:
        return " - "
    if v < 0:
        return f"({abs(v):,.2f})"
    return f" {v:,.2f} "

def _sum(series):
    return float(series.sum()) if not series.empty else 0.0

def _row(rtype, book="", desk="", portfolio="",
         mv="", daily="", mtd="", ytd=""):
    return dict(type=rtype, book=book, desk=desk, portfolio=portfolio,
                mv=mv, daily=daily, mtd=mtd, ytd=ytd)

# ── Build ─────────────────────────────────────────────────────────────────────
latest_date = pd.to_datetime(df["Business_Date"].max())
report_date = latest_date.strftime("%-m/%-d/%Y")   # Linux/Mac
# report_date = latest_date.strftime("%#m/%#d/%Y") # ← use this on Windows

rows = []

for book in BOOK_ORDER:
    book_df = df[df["Portfolio_Level_1"] == book]
    if book_df.empty:
        print(f"⚠️  No data found for Book: '{book}' — skipping.")
        continue

    rows.append(_row("book_header", book=book))
    desks = book_df["Portfolio_Level_2"].dropna().unique()

    for desk in desks:
        desk_df    = book_df[book_df["Portfolio_Level_2"] == desk]
        portfolios = desk_df["Portfolio_Level_3"].dropna().unique()

        for portfolio in portfolios:
            port_df  = desk_df[desk_df["Portfolio_Level_3"] == portfolio]
            main_df  = port_df[~port_df["Deal_Type"].isin(DB_DEAL_TYPES)]
            bm_df    = port_df[port_df["Deal_Type"] == "Benchmark"]
            ftp_df   = port_df[port_df["Deal_Type"] == "FTP"]

            mv_val    = _sum(main_df["MV_USD"])
            daily_val = _sum(main_df["DTD_PnL_USD"])
            mtd_val   = _sum(main_df["MTD_PnL_USD"])
            ytd_val   = _sum(main_df["YTD_PnL_USD"])

            rows.append(_row("portfolio", desk=desk, portfolio=portfolio,
                             mv=fmt(mv_val), daily=fmt(daily_val),
                             mtd=fmt(mtd_val), ytd=fmt(ytd_val)))

            bm_daily = _sum(bm_df["DTD_PnL_USD"])
            bm_mtd   = _sum(bm_df["MTD_PnL_USD"])
            bm_ytd   = _sum(bm_df["YTD_PnL_USD"])

            rows.append(_row("sub", portfolio="Benchmark", mv=" - ",
                             daily=fmt(bm_daily) if not bm_df.empty else " - ",
                             mtd=fmt(bm_mtd)     if not bm_df.empty else " - ",
                             ytd=fmt(bm_ytd)     if not bm_df.empty else " - "))

            rows.append(_row("sub", portfolio="Relative", mv="",
                             daily=fmt(daily_val - bm_daily),
                             mtd=fmt(mtd_val   - bm_mtd),
                             ytd=fmt(ytd_val   - bm_ytd)))

            ftp_mv    = _sum(ftp_df["MV_USD"])     if not ftp_df.empty else None
            ftp_daily = _sum(ftp_df["DTD_PnL_USD"]) if not ftp_df.empty else None
            ftp_mtd   = _sum(ftp_df["MTD_PnL_USD"]) if not ftp_df.empty else None
            ftp_ytd   = _sum(ftp_df["YTD_PnL_USD"]) if not ftp_df.empty else None

            rows.append(_row("sub", portfolio="FTP",
                             mv=fmt(ftp_mv)    if ftp_mv    is not None else "#N/A",
                             daily=fmt(ftp_daily) if ftp_daily is not None else "#N/A",
                             mtd=fmt(ftp_mtd)  if ftp_mtd   is not None else "#N/A",
                             ytd=fmt(ftp_ytd)  if ftp_ytd   is not None else "#N/A"))

        # Desk total
        d_main = desk_df[~desk_df["Deal_Type"].isin(DB_DEAL_TYPES)]
        d_ftp  = desk_df[desk_df["Deal_Type"] == "FTP"]
        rows.append(_row("desk_total", desk="Total",
                         mv=fmt(_sum(d_main["MV_USD"])),
                         daily=fmt(_sum(d_main["DTD_PnL_USD"])),
                         mtd=fmt(_sum(d_main["MTD_PnL_USD"])),
                         ytd=fmt(_sum(d_main["YTD_PnL_USD"]))))
        rows.append(_row("sub", portfolio="Benchmark",
                         mv=" - ", daily=" - ", mtd=" - ", ytd=" - "))
        rows.append(_row("sub", portfolio="Relative", mv="",
                         daily=fmt(_sum(d_main["DTD_PnL_USD"])),
                         mtd=fmt(_sum(d_main["MTD_PnL_USD"])),
                         ytd=fmt(_sum(d_main["YTD_PnL_USD"]))))
        rows.append(_row("sub", portfolio="FTP",
                         mv=fmt(_sum(d_ftp["MV_USD"])),
                         daily=fmt(_sum(d_ftp["DTD_PnL_USD"])),
                         mtd=fmt(_sum(d_ftp["MTD_PnL_USD"])),
                         ytd=fmt(_sum(d_ftp["YTD_PnL_USD"]))))

    # Book grand total
    b_main = book_df[~book_df["Deal_Type"].isin(DB_DEAL_TYPES)]
    rows.append(_row("grand_total", book="Total",
                     mv=fmt(_sum(b_main["MV_USD"])),
                     daily=fmt(_sum(b_main["DTD_PnL_USD"])),
                     mtd=fmt(_sum(b_main["MTD_PnL_USD"])),
                     ytd=fmt(_sum(b_main["YTD_PnL_USD"]))))
    rows.append(_row("blank"))

print(f"✅ Report rows built: {len(rows)} rows total.")
print()

# ── Print a text preview of the report structure ──────────────────────────────
print(f"{'TYPE':<15} {'BOOK':<18} {'DESK':<20} {'PORTFOLIO':<30} {'MV':>15} {'DAILY':>15} {'MTD':>15} {'YTD':>15}")
print("-" * 135)
for r in rows:
    if r["type"] == "blank":
        print()
        continue
    print(f"{r['type']:<15} {r['book']:<18} {r['desk']:<20} {r['portfolio']:<30} "
          f"{r['mv']:>15} {r['daily']:>15} {r['mtd']:>15} {r['ytd']:>15}")
```

---

## Cell 5 — Generate PDF

> **Validation checkpoint:** Open the generated PDF from the `./output/` folder
> and compare it visually against the management template before sending.

```python
# ── Colour palette ────────────────────────────────────────────────────────────
DARK_BLUE  = colors.HexColor("#1F3864")
MED_BLUE   = colors.HexColor("#2E5EAA")
LIGHT_BLUE = colors.HexColor("#D6E4F0")
LIGHT_GRAY = colors.HexColor("#F5F5F5")
RED        = colors.HexColor("#C00000")
GRAY_TEXT  = colors.HexColor("#555555")

def is_negative(text):
    return isinstance(text, str) and text.strip().startswith("(")

def _para(text, align="RIGHT", bold=False, color=colors.black, size=8):
    style = ParagraphStyle(
        "cell",
        fontName="Helvetica-Bold" if bold else "Helvetica",
        fontSize=size,
        textColor=color,
        alignment={"RIGHT": TA_RIGHT, "LEFT": TA_LEFT, "CENTER": TA_CENTER}[align],
        leading=size + 2,
    )
    return Paragraph(str(text), style)

def _num_cell(text, bold=False, size=8):
    c = RED if is_negative(text) else colors.black
    return _para(text, align="RIGHT", bold=bold, color=c, size=size)

# ── Build PDF ─────────────────────────────────────────────────────────────────
filename    = f"LAM_Daily_Report_{report_date.replace('/', '-')}.pdf"
output_path = os.path.join(OUTPUT_DIR, filename)

doc   = SimpleDocTemplate(output_path, pagesize=landscape(A3),
                           leftMargin=0.4*inch, rightMargin=0.4*inch,
                           topMargin=0.5*inch,  bottomMargin=0.4*inch)
story = []

story.append(_para("IFC Treasury — LAM Sub-Account Summary",
                   align="LEFT", bold=True, color=DARK_BLUE, size=13))
story.append(_para(f"Business Date: {report_date}",
                   align="LEFT", color=GRAY_TEXT, size=9))
story.append(_para("CONFIDENTIAL — For Internal Management Distribution Only",
                   align="RIGHT", bold=True, color=RED, size=9))
story.append(Spacer(1, 0.12 * inch))

col_w = [1.0*inch, 2.1*inch, 2.5*inch, 2.5*inch, 2.5*inch, 2.5*inch, 2.5*inch]

hdr1 = [_para(report_date, "LEFT",   bold=True, color=colors.white, size=8),
         _para("Desk",      "LEFT",   bold=True, color=colors.white, size=8),
         _para("Portfolio", "LEFT",   bold=True, color=colors.white, size=8),
         _para("Market Value (USD)", "CENTER", bold=True, color=colors.white, size=8),
         _para("P&L",       "CENTER", bold=True, color=colors.white, size=8),
         _para("",          "CENTER", bold=True, color=colors.white, size=8),
         _para("",          "CENTER", bold=True, color=colors.white, size=8)]

hdr2 = [_para("Book",          "LEFT",  bold=True, color=colors.white, size=8),
         _para("",              "LEFT",  bold=True, color=colors.white, size=8),
         _para("",              "LEFT",  bold=True, color=colors.white, size=8),
         _para("MV (000's)",    "RIGHT", bold=True, color=colors.white, size=8),
         _para("Daily (000's)", "RIGHT", bold=True, color=colors.white, size=8),
         _para("MTD (000's)",   "RIGHT", bold=True, color=colors.white, size=8),
         _para("YTD (000's)",   "RIGHT", bold=True, color=colors.white, size=8)]

table_data  = [hdr1, hdr2]
style_cmds  = [
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

ri, alt = 2, False

for r in rows:
    rtype = r["type"]
    if rtype == "blank":
        table_data.append([_para("") for _ in range(7)])
        style_cmds.append(("ROWHEIGHT", (0, ri), (-1, ri), 5))
        ri += 1
    elif rtype == "book_header":
        table_data.append([_para(r["book"], "LEFT", bold=True, color=colors.white, size=9),
                           *[_para("") for _ in range(6)]])
        style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), MED_BLUE))
        ri += 1; alt = False
    elif rtype == "grand_total":
        table_data.append([_para("Total", "LEFT", bold=True, size=8),
                           _para(""), _para(""),
                           _num_cell(r["mv"],    bold=True, size=8),
                           _num_cell(r["daily"], bold=True, size=8),
                           _num_cell(r["mtd"],   bold=True, size=8),
                           _num_cell(r["ytd"],   bold=True, size=8)])
        style_cmds += [("BACKGROUND", (0, ri), (-1, ri), LIGHT_BLUE),
                       ("LINEABOVE",  (0, ri), (-1, ri), 0.8, DARK_BLUE)]
        ri += 1
    elif rtype == "desk_total":
        table_data.append([_para(""),
                           _para("Total", "LEFT", bold=True, size=8), _para(""),
                           _num_cell(r["mv"],    bold=True, size=8),
                           _num_cell(r["daily"], bold=True, size=8),
                           _num_cell(r["mtd"],   bold=True, size=8),
                           _num_cell(r["ytd"],   bold=True, size=8)])
        style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), LIGHT_BLUE))
        ri += 1
    elif rtype == "portfolio":
        bg = LIGHT_GRAY if alt else colors.white; alt = not alt
        table_data.append([_para(""),
                           _para(r["desk"],      "LEFT", bold=True,  size=8),
                           _para(r["portfolio"], "LEFT", bold=False, size=8),
                           _num_cell(r["mv"],    size=8),
                           _num_cell(r["daily"], size=8),
                           _num_cell(r["mtd"],   size=8),
                           _num_cell(r["ytd"],   size=8)])
        style_cmds.append(("BACKGROUND", (0, ri), (-1, ri), bg))
        ri += 1
    elif rtype == "sub":
        lbl  = r["portfolio"]
        bold = lbl == "Relative"
        table_data.append([_para(""), _para(""),
                           _para(f"      {lbl}", "LEFT", bold=bold, color=GRAY_TEXT, size=7),
                           _para(r["mv"],    "RIGHT", bold=bold,
                                 color=RED if is_negative(r["mv"])    else GRAY_TEXT, size=7),
                           _para(r["daily"], "RIGHT", bold=bold,
                                 color=RED if is_negative(r["daily"]) else GRAY_TEXT, size=7),
                           _para(r["mtd"],   "RIGHT", bold=bold,
                                 color=RED if is_negative(r["mtd"])   else GRAY_TEXT, size=7),
                           _para(r["ytd"],   "RIGHT", bold=bold,
                                 color=RED if is_negative(r["ytd"])   else GRAY_TEXT, size=7)])
        ri += 1

table = Table(table_data, colWidths=col_w, repeatRows=2)
table.setStyle(TableStyle(style_cmds))
story.append(table)
story.append(Spacer(1, 0.12 * inch))
story.append(_para(
    f"Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}  |  "
    "IFC Treasury Operations  |  CONFIDENTIAL",
    align="CENTER", color=GRAY_TEXT, size=7))

doc.build(story)
print(f"✅ PDF generated: {output_path}")
print(f"   → Open the file and compare it against the management template before proceeding.")
```

---

## Cell 6 — Send Email

> **Important:** Only run this cell once you are **fully satisfied** with the PDF output.
> Send a test to yourself first by temporarily replacing `TO_EMAILS` with your own address.

```python
# ── Safety check — send to yourself first during testing ─────────────────────
TEST_MODE     = True                        # ← set to False for production send
TEST_RECIPIENT = "your.name@ifc.org"       # ← replace with your own email

recipients_to = [TEST_RECIPIENT] if TEST_MODE else TO_EMAILS
recipients_cc = []                if TEST_MODE else CC_EMAILS

if TEST_MODE:
    print("⚠️  TEST MODE — email will be sent to you only, not to the full distribution list.")

subject = f"[CONFIDENTIAL] IFC Treasury LAM Daily Report — {report_date}"
body = (
    f"Dear Team,\n\n"
    f"Please find attached the IFC Treasury LAM Sub-Account Summary for {report_date}.\n\n"
    f"This report is confidential and intended for authorised management distribution only.\n\n"
    f"Regards,\n"
    f"IFC Treasury Operations\n\n"
    f"--- This is an automated message. Please do not reply. ---"
)

msg           = MIMEMultipart()
msg["From"]   = FROM_EMAIL
msg["To"]     = ", ".join(recipients_to)
msg["CC"]     = ", ".join(recipients_cc)
msg["Subject"]= subject
msg.attach(MIMEText(body, "plain"))

with open(output_path, "rb") as f:
    part = MIMEBase("application", "octet-stream")
    part.set_payload(f.read())
    encoders.encode_base64(part)
    part.add_header("Content-Disposition",
                    f'attachment; filename="{os.path.basename(output_path)}"')
    msg.attach(part)

all_recipients = recipients_to + recipients_cc
with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
    server.sendmail(FROM_EMAIL, all_recipients, msg.as_string())

print(f"✅ Email sent to: {', '.join(all_recipients)}")
```

---

## Testing Checklist

Work through this before promoting to production:

- [ ] **Cell 3:** Data fetched with no errors. Latest business date is correct.
- [ ] **Cell 3:** `Deal_Type` values match what the script expects (`Benchmark`, `FTP`). If not, update `DB_DEAL_TYPES` in Cell 4.
- [ ] **Cell 4:** Text preview hierarchy matches the template (Book → Desk → Portfolio → sub-rows).
- [ ] **Cell 4:** Relative values are computed correctly (Portfolio P&L − Benchmark P&L).
- [ ] **Cell 5:** PDF opens without errors and layout matches the template visually.
- [ ] **Cell 5:** Negative numbers show in red with parentheses. Zero values show as ` - `.
- [ ] **Cell 5:** FTP rows with no data show `#N/A` (e.g. Legacy INR Fixed Pool).
- [ ] **Cell 6:** Test email received with correct PDF attached.
- [ ] **Cell 6:** Set `TEST_MODE = False` and confirm final send to full distribution list.

---

*This document was generated by mAI.*
