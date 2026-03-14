# DCA AutoTrader EA สำหรับ MT5

Expert Advisor ระบบ DCA (Dollar Cost Averaging) อัตโนมัติ
รองรับ: **BTCUSD** และ **XAUUSD** บนพอร์ต **Cent Account**

---

## กลยุทธ์ (Strategy)

### สัญญาณเปิด Order (Entry Signal)
- **MA Crossover**: EMA 20 ตัดผ่าน EMA 50
  - ตัดขึ้น → BUY
  - ตัดลง → SELL
- **RSI Filter**: กรองสัญญาณที่ overbought/oversold เกินไป
  - BUY: RSI < 70 (ไม่ overbought)
  - SELL: RSI > 30 (ไม่ oversold)

### DCA Logic
เมื่อราคาวิ่งสวนทาง ระบบจะ **เพิ่ม lot** ตามระยะห่างที่กำหนด:

```
Level 0 (เปิดครั้งแรก): Lot = InpLotSize
Level 1 (DCA #1):        Lot = InpLotSize × DCAMultiplier^1
Level 2 (DCA #2):        Lot = InpLotSize × DCAMultiplier^2
...ไปจนถึง MaxDCALevels
```

หลัง DCA แต่ละครั้ง ระบบคำนวณ **ราคาเฉลี่ย (Average Price)** ใหม่
และอัปเดต Take Profit ทุก order ไปที่จุดเดียวกัน

### Take Profit / Stop Loss
| Parameter | คำอธิบาย |
|-----------|----------|
| TakeProfitPct | TP เป็น % จาก average entry price |
| StopLossPct   | SL เป็น % จาก first entry price  |
| TrailingPct   | Trailing Stop เป็น % จาก bid/ask |

---

## การติดตั้ง

1. คัดลอกไฟล์ `DCA_AutoTrader.mq5` ไปที่:
   ```
   MT5 Data Folder → MQL5 → Experts
   ```
2. เปิด MetaEditor แล้ว Compile ไฟล์
3. ลาก EA ไปวางบนกราฟ BTCUSD หรือ XAUUSD
4. โหลด Preset จากโฟลเดอร์ `presets/`

---

## Preset Settings

### BTCUSD Cent (`presets/BTCUSD_Cent.set`)
| Parameter | ค่า | หมายเหตุ |
|-----------|-----|---------|
| Timeframe | H1 | แนะนำ |
| Initial Lot | 0.01 | เล็กสุดสำหรับ cent |
| DCA Trigger | 2.0% | ราคาลง 2% → DCA |
| Max DCA Levels | 4 | สูงสุด 4 ครั้ง |
| TP | 2.0% | จาก avg price |
| SL | 5.0% | จาก first entry |
| Max Spread | 100 pts | BTC spread สูง |

### XAUUSD Cent (`presets/XAUUSD_Cent.set`)
| Parameter | ค่า | หมายเหตุ |
|-----------|-----|---------|
| Timeframe | H1 | แนะนำ |
| Initial Lot | 0.01 | เล็กสุดสำหรับ cent |
| DCA Trigger | 1.5% | ราคาลง 1.5% → DCA |
| Max DCA Levels | 5 | สูงสุด 5 ครั้ง |
| TP | 1.5% | จาก avg price |
| SL | 3.0% | จาก first entry |
| Session | 07:00-21:00 | London+NY session |

---

## ตัวอย่างการคำนวณ Capital ที่ต้องการ (XAUUSD Cent)

สมมติ Gold = $2,000/oz, Cent Account (×100)

| Level | Lot | จุด DCA | Capital ใช้ (est.) |
|-------|-----|---------|-------------------|
| 0 | 0.01 | - | ~$20 cent |
| 1 | 0.015 | -1.5% | ~$30 cent |
| 2 | 0.023 | -3.0% | ~$46 cent |
| 3 | 0.034 | -4.5% | ~$68 cent |
| 4 | 0.051 | -6.0% | ~$102 cent |
| **Total** | | | **~$266 cent** |

> แนะนำมีทุนอย่างน้อย **500-1000 cent** เพื่อรับ drawdown

---

## Risk Warning

> ⚠️ **คำเตือน**: EA นี้ใช้กลยุทธ์ DCA ซึ่งมีความเสี่ยงสูง
> ราคาที่วิ่งสวนทางนานๆ อาจทำให้ margin หมดได้
> ควร backtest และ forward test ก่อนใช้กับเงินจริงเสมอ

### การบริหารความเสี่ยง
- ตั้ง `MaxDDPercent` ไว้ที่ 20% เพื่อหยุดเทรดอัตโนมัติเมื่อ drawdown เกิน
- ไม่ควรตั้ง `MaxDCALevels` เกิน 5 ในพอร์ตเล็ก
- ทดสอบใน **Strategy Tester** ก่อนเสมอ

---

## Parameters Reference

| Parameter | Default | คำอธิบาย |
|-----------|---------|----------|
| InpMagicNumber | 202400 | Magic number ป้องกัน EA อื่นแทรก |
| InpLotSize | 0.01 | Lot เริ่มต้น |
| InpMaxLotSize | 0.5 | Lot สูงสุดรวม |
| InpFastMA | 20 | EMA เร็ว |
| InpSlowMA | 50 | EMA ช้า |
| InpRSIPeriod | 14 | RSI period |
| InpTakeProfitPct | 2.0 | TP % จาก avg price |
| InpStopLossPct | 5.0 | SL % จาก first entry |
| InpEnableDCA | true | เปิด/ปิด DCA |
| InpMaxDCALevels | 5 | จำนวน DCA สูงสุด |
| InpDCATriggerPct | 1.5 | % ราคาต้องลดก่อน DCA |
| InpDCAMultiplier | 1.5 | Lot multiplier ต่อ DCA level |
| InpMaxDDPercent | 20.0 | หยุดเทรดเมื่อ DD เกิน % |
| InpUseTrailing | true | เปิด Trailing Stop |
| InpTrailingPct | 1.0 | Trailing distance % |
| InpUseSession | false | กรองเวลาเทรด |
| InpMaxSpread | 50 | Spread สูงสุดที่ยอมรับ |
