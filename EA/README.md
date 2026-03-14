# DCA AutoTrader v2 — MT5 Expert Advisor

Trend-Following DCA EA สำหรับ **BTCUSD** และ **XAUUSD**
ออกแบบสำหรับพอร์ต **$500 USD** (Cent / Standard Account)

---

## กลยุทธ์โดยรวม

```
H4 Trend Filter ──→ กำหนดทิศทาง (ขาขึ้น/ขาลง)
       │
       ▼
H1 Entry Signal ──→ EMA20 ตัด EMA50 + RSI
       │
       ▼
   เปิด Order ──→ ทิศทางเดียวกับ Trend เท่านั้น
       │
       ▼
  DCA (ถ้าราคาย้อน) ──→ เพิ่ม lot ตาม trend
       │
       ▼
Trend เปลี่ยน? ──→ ปิดทุก Order → รอสัญญาณใหม่
```

---

## ขั้นตอนการทำงาน

### 1. Trend Filter (H4 Timeframe)
| เงื่อนไข | ทิศทาง | EA ทำอะไร |
|---------|--------|-----------|
| ราคา > EMA200 (H4) + ADX > 20 | **ขาขึ้น** | เปิดได้เฉพาะ **BUY** |
| ราคา < EMA200 (H4) + ADX > 20 | **ขาลง**  | เปิดได้เฉพาะ **SELL** |
| ADX < 20 | Sideways | **ไม่เปิด Order** |

### 2. Entry Signal (H1 Timeframe)
- **BUY entry**: EMA20 ตัดขึ้นผ่าน EMA50 + RSI < 65
- **SELL entry**: EMA20 ตัดลงผ่าน EMA50 + RSI > 35

### 3. DCA (เมื่อราคาย้อน)
- ราคาย้อนกลับ % ที่กำหนด → เพิ่ม Order ในทิศทางเดิม
- TP คำนวณใหม่จาก **weighted average price**
- ทำได้สูงสุด MaxDCALevels ครั้ง

### 4. Trend Reversal
- เมื่อ H4 trend เปลี่ยน → **ปิด Order ทั้งหมด** → รอสัญญาณใหม่
- ยืนยัน reversal ด้วย `ReversalConfirm` แท่ง (ป้องกัน whipsaw)

---

## การคำนวณ Lot Size (Risk-based)

```
Risk Amount  = Balance × RiskPercent%
               $500    × 1%          = $5 ต่อ trade

SL Distance  = Entry Price × SL%
               (XAUUSD $2,000) × 2% = $40

Lot Size     = Risk Amount / (SL_points × TickValue)
             = $5 / ($40 / point × tickval)
```

### ตัวอย่างจริงสำหรับ $500 บัญชี Standard

| Symbol | Balance | Risk | SL | Lot คาดการณ์ |
|--------|---------|------|----|-------------|
| XAUUSD | $500 | 1% = $5 | 2% (~$40) | ~0.01 lot |
| BTCUSD | $500 | 1% = $5 | 2.5% (~$2,500) | ~0.001 lot |

> บัญชี Cent: Balance แสดง ×100 แต่ lot calculation ใช้ค่า equity จริงอยู่แล้ว

---

## การติดตั้ง

1. คัดลอก `DCA_AutoTrader.mq5` → `MT5 Data Folder/MQL5/Experts/`
2. เปิด MetaEditor → Compile (F7)
3. ลาก EA วางบนกราฟ **BTCUSD** หรือ **XAUUSD** ที่ Timeframe **H1**
4. ใน EA Properties → Load preset จาก `presets/`
5. เปิด **Allow Algo Trading**

---

## Preset สรุป

### BTCUSD (`presets/BTCUSD_Cent.set`)
| Setting | Value |
|---------|-------|
| Trend TF | H4 + EMA200 + ADX |
| Entry TF | H1 |
| Risk per trade | 1% |
| Stop Loss | 2.5% |
| Take Profit | 4.0% |
| DCA Trigger | 2.0% |
| Max DCA | 3 levels |
| Close on Reversal | Yes |

### XAUUSD (`presets/XAUUSD_Cent.set`)
| Setting | Value |
|---------|-------|
| Trend TF | H4 + EMA200 + ADX |
| Entry TF | H1 |
| Risk per trade | 1% |
| Stop Loss | 2.0% |
| Take Profit | 3.0% |
| DCA Trigger | 1.5% |
| Max DCA | 4 levels |
| Session | 07:00-21:00 (London/NY) |

---

## Capital Requirement (ประมาณการ) สำหรับ $500

### Worst-case DCA scenario (XAUUSD Standard Account)

| Level | Lot | Drawdown จาก SL |
|-------|-----|----------------|
| Entry | 0.01 | $0 |
| DCA #1 | 0.015 | ~$6 |
| DCA #2 | 0.023 | ~$18 |
| DCA #3 | 0.034 | ~$38 |
| DCA #4 | 0.051 | ~$70 |
| **Worst case** | | **~$132** (26% of $500) |

> Max DD guard ตั้งที่ 20% = หยุดเมื่อ equity ลดลง $100

---

## Parameters Reference

| Parameter | Default | คำอธิบาย |
|-----------|---------|---------|
| `InpTrendTF` | H4 | Timeframe สำหรับ trend filter |
| `InpTrendMA` | 200 | EMA period สำหรับ trend |
| `InpUseADX` | true | ใช้ ADX ยืนยัน trend strength |
| `InpADXMinLevel` | 20 | ADX ต่ำกว่านี้ = sideways ไม่เทรด |
| `InpFastMA` | 20 | EMA เร็วสำหรับ entry |
| `InpSlowMA` | 50 | EMA ช้าสำหรับ entry |
| `InpRiskPercent` | 1.0 | % ของ balance ที่ยอมเสียต่อ trade |
| `InpSLPercent` | 2.0 | Stop Loss % จาก entry price |
| `InpTPPercent` | 3.0 | Take Profit % จาก avg price |
| `InpEnableDCA` | true | เปิด DCA |
| `InpMaxDCALevels` | 4 | จำนวน DCA สูงสุด |
| `InpDCATriggerPct` | 1.5 | % ราคาต้องย้อนก่อน DCA |
| `InpDCALotMultiply` | 1.5 | ขยาย lot แต่ละ DCA level |
| `InpCloseOnReversal` | true | ปิด order เมื่อ trend เปลี่ยน |
| `InpReversalConfirm` | 2 | จำนวนแท่งยืนยัน reversal |
| `InpMaxDDPercent` | 20 | หยุดเทรดเมื่อ drawdown เกิน % |
| `InpUseTrailing` | true | เปิด trailing stop |
| `InpTrailingPercent` | 1.0 | Trailing distance % |

---

## ข้อควรระวัง

> ⚠️ ควร **Backtest** ใน MT5 Strategy Tester ก่อนใช้เงินจริงเสมอ
>
> ระบบ DCA มีความเสี่ยงสูง หากตลาดวิ่งสวนทางนาน margin อาจหมดได้
>
> แนะนำใช้พอร์ต Cent สำหรับการทดสอบในตลาดจริงก่อน
