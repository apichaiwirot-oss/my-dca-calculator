import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime

# 1. ตั้งค่าหน้าเว็บและสไตล์
st.set_page_config(page_title="Pro DCA Calculator", layout="wide")
st.title("📈 DCA Investment Simulator")
st.markdown("---")

# 2. Sidebar สำหรับตั้งค่า
st.sidebar.header("🔍 ตั้งค่าการลงทุน")
ticker = st.sidebar.text_input("ชื่อหุ้น/คริปโต (เช่น NVDA, BTC-USD, PTT.BK)", value="NVDA").upper()
monthly_investment = st.sidebar.number_input("เงินลงทุนต่อเดือน (บาท/USD)", min_value=100.0, value=5000.0, step=500.0)
start_date = st.sidebar.date_input("วันที่เริ่มลงทุน", value=datetime(2023, 1, 1))

if st.sidebar.button("🚀 ประมวลผลข้อมูล"):
    with st.spinner('กำลังดึงข้อมูลจาก Yahoo Finance...'):
        data = yf.download(ticker, start=start_date, progress=False)
        
        if not data.empty:
            # คำนวณ Logic
            monthly_data = data['Close'].resample('MS').first().dropna()
            dca_df = pd.DataFrame(index=monthly_data.index)
            dca_df['ราคาซื้อ'] = monthly_data.values
            dca_df['จำนวนหุ้นที่ได้'] = monthly_investment / dca_df['ราคาซื้อ']
            dca_df['หุ้นสะสม'] = dca_df['จำนวนหุ้นที่ได้'].cumsum()
            dca_df['เงินต้นสะสม'] = [monthly_investment * i for i in range(1, len(dca_df)+1)]
            dca_df['มูลค่าพอร์ต'] = dca_df['หุ้นสะสม'] * dca_df['ราคาซื้อ']
            
            # ข้อมูลสรุปสุดท้าย
            total_invested = dca_df['เงินต้นสะสม'].iloc[-1]
            current_value = dca_df['มูลค่าพอร์ต'].iloc[-1]
            net_profit = current_value - total_invested
            roi = (net_profit / total_invested) * 100

            # 3. แสดง Dashboard สรุปผล
            st.subheader("📊 สรุปภาพรวมพอร์ตการลงทุน")
            m1, m2, m3, m4 = st.columns(4)
            m1.metric("เงินต้นทั้งหมด", f"{total_invested:,.2f}")
            m2.metric("มูลค่าปัจจุบัน", f"{current_value:,.2f}")
            m3.metric("กำไร/ขาดทุน (สุทธิ)", f"{net_profit:,.2f}", f"{roi:.2f}%")
            m4.metric("ราคาล่าสุด", f"{dca_df['ราคาซื้อ'].iloc[-1]:,.2f}")

            # 4. แสดงกราฟ Interactive
            fig = go.Figure()
            fig.add_trace(go.Scatter(x=dca_df.index, y=dca_df['เงินต้นสะสม'], name="เงินต้นสะสม", line=dict(color='#3498db', width=2)))
            fig.add_trace(go.Scatter(x=dca_df.index, y=dca_df['มูลค่าพอร์ต'], name="มูลค่าพอร์ต", fill='tozeroy', line=dict(color='#2ecc71', width=3)))
            fig.update_layout(title=f"การเติบโตของพอร์ต {ticker}", hovermode="x unified", template="plotly_dark")
            st.plotly_chart(fig, use_container_width=True)

            # 5. ตารางรายละเอียด
            with st.expander("📂 ดูรายละเอียดการซื้อรายเดือน"):
                formatted_df = dca_df.copy()
                st.dataframe(formatted_df.style.format("{:,.2f}"), use_container_width=True)
        else:
            st.error("⚠️ ไม่พบข้อมูลหุ้นตัวนี้ กรุณาตรวจสอบชื่อสัญลักษณ์อีกครั้ง")