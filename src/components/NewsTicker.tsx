const NEWS_ITEMS = [
  '🔴 Fed คงดอกเบี้ย 5.25-5.50% ต่อเนื่อง · นักวิเคราะห์คาดลดครั้งแรกในปีนี้',
  '📊 S&P 500 ทำ All-Time High ใหม่ หลังข้อมูล CPI เดือนมีนาคมดีกว่าคาด',
  '🇹🇭 SET Index ปรับตัวขึ้น 5.67 จุด นำโดยกลุ่ม Banking · PTT · CPALL',
  '💰 Bitcoin ทะลุ $85,000 หลัง BlackRock Spot ETF มีเงินไหลเข้าสูงสุดในรอบเดือน',
  '🥇 ทองคำแตะ $3,053/oz · Gold Futures สูงสุดนับตั้งแต่ปี 2024',
  '🇺🇸 GDP สหรัฐฯ ไตรมาส 4 ขยายตัว 2.3% ดีกว่าที่ตลาดคาดไว้ที่ 2.0%',
  '⚡ NVIDIA (NVDA) รายงานกำไร Q4 เกินคาด · Datacenter Revenue โต 206% YoY',
  '🏦 Goldman Sachs ปรับเป้า S&P 500 ปีนี้เป็น 6,500 จุด จาก 6,000 จุด',
  '🛢️ น้ำมัน Brent ดีดขึ้น $82.40/bbl หลัง OPEC+ ยืนยันยังคงลดการผลิตต่อ',
  '🇯🇵 Bank of Japan ขึ้นดอกเบี้ยสู่ 0.5% สูงสุดในรอบ 17 ปี · เยนแข็งค่า',
  '💹 เงินบาทแข็งค่าสู่ 34.15 บาท/USD จากแรงขายดอลลาร์ในตลาดเอเชีย',
  '🚗 Tesla Q4: ยอดส่งมอบรถ 495,000 คัน สูงสุดตลอดกาล ราคาหุ้น +8%',
  '🤖 Apple ประกาศ Apple Intelligence ใหม่ ใช้ Claude ของ Anthropic เป็น AI หลัก',
  '📉 Hang Seng ร่วง 1.2% หลังสหรัฐฯ ประกาศเพิ่ม Tariff สินค้าจีนอีก 10%',
  '🇨🇳 China NBS: PMI ภาคการผลิตเดือนมีนาคม 50.8 สูงกว่าระดับขยายตัว',
  '🔋 ราคา Lithium ฟื้นตัว +15% ในเดือนเดียว หลัง EV demand ในจีนฟื้น',
]

export default function NewsTicker() {
  const combined = [...NEWS_ITEMS, ...NEWS_ITEMS]

  return (
    <div className="bg-[#0f0f0f] border-b border-[#1e1e1e] overflow-hidden" style={{ height: '28px' }}>
      <div className="flex items-stretch h-full">
        {/* Label */}
        <div className="flex-shrink-0 flex items-center gap-2 px-3 bg-[#1a1a1a] border-r border-[#2a2a2a]">
          <span className="text-[10px] font-bold tracking-widest text-[#E50914]">📰 ข่าว</span>
        </div>

        {/* Scrolling news */}
        <div className="flex-1 overflow-hidden">
          <div className="news-track h-full items-center">
            {combined.map((item, i) => (
              <span key={i} className="flex items-center h-full flex-shrink-0 whitespace-nowrap">
                <span className="text-[#999] text-[11px] px-4">{item}</span>
                <span className="text-[#2a2a2a] text-[10px]">◆</span>
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
