# email/sender.py and lam_daily_report.py (Production Entry Point)

---

## File: `email/sender.py`

```python
# email/sender.py
# ─────────────────────────────────────────────────────────────────────────────
# Email assembly and SMTP distribution for the LAM Daily Confidential Report.
# ─────────────────────────────────────────────────────────────────────────────

import logging
import os
import smtplib
from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

logger = logging.getLogger("lam_report")


def send_report(
    pdf_path: str,
    report_date: str,
    smtp_server: str,
    smtp_port: int,
    from_email: str,
    to_emails: list,
    cc_emails: list,
    test_mode: bool = False,
    test_recipient: str = "",
) -> None:
    """
    Send the LAM Daily PDF report via SMTP.

    Args:
        pdf_path:        Full path to the generated PDF file.
        report_date:     Formatted date string for the email subject.
        smtp_server:     SMTP relay hostname.
        smtp_port:       SMTP port (typically 25 for internal relay).
        from_email:      Sender address.
        to_emails:       Full management distribution list.
        cc_emails:       CC recipients.
        test_mode:       If True, sends only to test_recipient (not full list).
        test_recipient:  Email address used when test_mode=True.

    Raises:
        FileNotFoundError: If the PDF file does not exist.
        smtplib.SMTPException: If the SMTP send fails.
    """
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"PDF not found: {pdf_path}")

    if test_mode:
        recipients_to = [test_recipient]
        recipients_cc = []
        logger.warning(f"TEST MODE — sending only to: {test_recipient}")
    else:
        recipients_to = to_emails
        recipients_cc = cc_emails

    subject = f"[CONFIDENTIAL] IFC Treasury LAM Daily Report — {report_date}"
    body = (
        f"Dear Team,\n\n"
        f"Please find attached the IFC Treasury LAM Sub-Account Summary "
        f"for {report_date}.\n\n"
        f"This report is confidential and intended for authorised "
        f"management distribution only.\n\n"
        f"Regards,\n"
        f"IFC Treasury Operations\n\n"
        f"--- This is an automated message. Please do not reply. ---"
    )

    msg             = MIMEMultipart()
    msg["From"]     = from_email
    msg["To"]       = ", ".join(recipients_to)
    msg["CC"]       = ", ".join(recipients_cc)
    msg["Subject"]  = subject
    msg.attach(MIMEText(body, "plain"))

    with open(pdf_path, "rb") as f:
        part = MIMEBase("application", "octet-stream")
        part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header(
            "Content-Disposition",
            f'attachment; filename="{os.path.basename(pdf_path)}"',
        )
        msg.attach(part)

    all_recipients = recipients_to + recipients_cc
    with smtplib.SMTP(smtp_server, smtp_port) as server:
        server.sendmail(from_email, all_recipients, msg.as_string())

    logger.info(f"Email sent to: {', '.join(all_recipients)}")
```

---

## File: `email/__init__.py`

```python
# email/__init__.py
# Makes email a package.
```

---

## File: `lam_daily_report.py` — Production Entry Point

```python
# lam_daily_report.py
# ─────────────────────────────────────────────────────────────────────────────
# IFC Treasury — LAM Daily Confidential Report
# Production entry point.
#
# Usage:
#   python lam_daily_report.py
#
# Schedule:
#   Windows Task Scheduler or Linux cron — see README.md for instructions.
# ─────────────────────────────────────────────────────────────────────────────

import os
import sys
from datetime import datetime

# ── Configuration ─────────────────────────────────────────────────────────────
from config import settings
from config.logging_config import setup_logger

# ── Application modules ───────────────────────────────────────────────────────
from src.db            import fetch_data
from src.builder       import build_rows
from src.pdf_generator import generate_pdf
from email.sender      import send_report


def main() -> None:
    # ── Logging ───────────────────────────────────────────────────────────────
    logger = setup_logger(log_dir=settings.LOG_DIR)
    logger.info("=" * 60)
    logger.info("IFC Treasury — LAM Daily Report — START")
    logger.info(f"Run time (UTC): {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 60)

    try:
        # ── Step 1: Fetch data ─────────────────────────────────────────────────
        logger.info("[1/4] Fetching data from FDL...")
        df = fetch_data(settings.CONNECTION_STRING)

        # ── Step 2: Build report rows ──────────────────────────────────────────
        logger.info("[2/4] Building report structure...")
        report_date, rows = build_rows(
            df,
            book_order=settings.BOOK_ORDER,
            db_deal_types=settings.DB_DEAL_TYPES,
        )

        # ── Step 3: Generate PDF ───────────────────────────────────────────────
        logger.info("[3/4] Generating PDF...")
        os.makedirs(settings.OUTPUT_DIR, exist_ok=True)
        filename    = f"LAM_Daily_Report_{report_date.replace('/', '-')}.pdf"
        output_path = os.path.join(settings.OUTPUT_DIR, filename)
        generate_pdf(report_date, rows, output_path)

        # ── Step 4: Send email ─────────────────────────────────────────────────
        logger.info("[4/4] Sending email...")
        send_report(
            pdf_path       = output_path,
            report_date    = report_date,
            smtp_server    = settings.SMTP_SERVER,
            smtp_port      = settings.SMTP_PORT,
            from_email     = settings.FROM_EMAIL,
            to_emails      = settings.TO_EMAILS,
            cc_emails      = settings.CC_EMAILS,
            test_mode      = False,   # ← set to True for testing
            test_recipient = "",      # ← your email address when test_mode=True
        )

        logger.info("=" * 60)
        logger.info("IFC Treasury — LAM Daily Report — COMPLETE")
        logger.info("=" * 60)

    except Exception as e:
        logger.exception(f"Pipeline failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

---

*This document was generated by mAI.*
