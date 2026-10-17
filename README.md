# Surabhi Export

Offline sales billing app (same flow as RKS sales) for a **single shop location**.

## Login

| Role | Username | Password |
|------|----------|----------|
| Staff | `surabhi` | `surabhi` |
| Admin | `admin` | `admin123` |

## Features

- **Master** menu: add item names (shirt, pant, etc.). They appear in the **particular** dropdown on the sales bill (before rate).
- **Payment** order: UPI, CASH, CARD (default UPI).
- Thermal receipt: **SNO**, **PARTICULAR**, **RATE**, **QTY**, **AMOUNT** with aligned columns; shop name prints larger on ESC/POS printers.
- Single local SQLite database (`main_sales.db`) — no sync required (sync menu hidden).

## Run

```bash
flutter pub get
flutter run -d windows
```
