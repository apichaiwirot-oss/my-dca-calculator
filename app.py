import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime

# --- 1. การตั้งค่าหน้าเว็บและ Style ---
st.set_page_config(page_title="Professional DCA Tool", layout="wide")

# ใช้ CSS แบบ Force Style (!important) เพื่อให้ทับค่ามาตรฐานของ Streamlit
st.markdown("""
    <style>
    /* พื้นหลังหลักดำสนิท */
    .stApp {
        background-color: #000000 !important;
    }
    
    /* ปรับแต่งแถบข้าง (Sidebar) */
    [data-testid="stSidebar"] {
        background-color: #141414 !important;
    }

    /* ปรับแต่ง Metric Cards ให้เป็น Netflix Style */
    [data-testid="stMetric"] {
        background-color: #141414 !important;
        border: 1px solid #333333 !important;
        border-radius: 10px !important;
        padding: 20px !important;
        box-shadow: 0 4px 15px rgba(0,0,0,0.5) !important;
    }
    
    /* กล่องสรุปผลกำไรหลัก */
    .main-result {
        background-color: #141414 !important;
        border-radius: 15px !important;
        padding: 40px !important;
        border: 1px solid #E50914 !important;
        text-align: center;
        margin-bottom: 25px;
    }

    /* สีข้อความทั้งหมด */
    h1, h2, h3, p, span, label {
        color: #FFFFFF !important;
    }
    
    /* ปรับแต่งปุ่มกดสีแดง Netflix */
    div.stButton > button {
        background-color: #E50914 !important;
        color: white !important;
        border: none !important;
        border-radius: 4px !important;
        font-weight: bold !important;
        padding: 12px 24px !important;
        width: 100% !important;
    }
    
    div.stButton > button:hover {
        background-color: #B20710 !important;
        transform: scale(1.02);
    }

    /* ปรับแต่งช่องกรอกข้อมูล */
    input {
        background-color: #2F2F2F !important;
        color: white !important;
        border-radius: 5px !important;
    }
    </style>
    """, unsafe_allow_html=True)

# --- 2. ส่วนหัวของเว็บไซต์ ---
st.title("🎯 เครื่องคำนวณ DCA")
st.write("วางแผนการลงทุนแบบถัวเฉลี่ย สไตล์วิศวกรการเงิน")

# --- 3. ส่วนรับข้อมูล ---
with st.container():
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        ticker = st.text_input("ชื่อหุ้น/คริปโต", value="NVDA").upper()
    with col2:
        monthly_investment = st.number_input("เงินลงทุนต่อเดือน (฿)", min_value=0, value=5000)
    with col3:
        start_date = st.date_input("วันที่เริ่มลงทุน", value=datetime(2023, 1, 1))
    with col4:
        st.write(" ") # สร้างช่องว่าง
        run_button = st.button("🚀 คำนวณผลลัพธ์")

# --- 4. ส่วนประมวลผล ---
if run_button:
    try:
        with st.spinner('กำลังดึงข้อมูลจาก Yahoo Finance...'):
            data = yf.download(ticker, start=start_date, progress=False)
            
            if not data.empty:
                # Logic การคำนวณ DCA
                # จัดการข้อมูลราคาทุกต้นเดือน
                monthly_prices = data['Close'].resample('MS').first().dropna()
                
                total_shares = 0
                total_invested = 0
                
                for price in monthly_prices:
                    total_shares += monthly_investment / price
                    total_invested += monthly_investment
                
                current_price = data['Close'].iloc[-1]
                current_value = float(total_shares * current_price)
                profit = current_value - total_invested
                roi = (profit / total_invested) * 100

                # --- แสดงผล UI ---
                st.markdown(f"""
                    <div class="main-result">
                        <p style="margin:0; font-size:1.2rem; color:#B3B3B3 !important;">มูลค่าพอร์ตปัจจุบันของ {ticker}</p>
                        <h1 style="font-size:3.5rem; margin:10px 0;">฿{current_value:,.2f}</h1>
                    </div>
                """, unsafe_allow_html=True)

                res_col1, res_col2 = st.columns(2)
                res_col1.metric("เงินต้นทั้งหมด", f"฿{total_invested:,.2f}")
                res_col2.metric("กำไร/ขาดทุน", f"฿{profit:,.2f}", f"{roi:.2f}%")

                # กราฟ
                st.markdown("### 📈 กราฟการเติบโตของพอร์ต")
                fig = go.Figure()
                # ปรับแต่งกราฟให้เข้ากับ Dark Mode
                fig.add_trace(go.Scatter(y=data['Close'], x=data.index, name="ราคาตลาด", line=dict(color='#E50914')))
                fig.update_layout(
                    template="plotly_dark",
                    paper_bgcolor='rgba(0,0,0,0)',
                    plot_bgcolor='rgba(0,0,0,0)',
                    height=400
                )
                st.plotly_chart(fig, use_container_width=True)

            else:
                st.error("⚠️ ไม่พบข้อมูลหุ้น โปรดใช้ชื่อ Ticker ที่ถูกต้อง เช่น PTT.BK หรือ BTC-USD")
    except Exception as e:
        st.error(f"เกิดข้อผิดพลาด: {e}")

# ฟุตเตอร์
st.markdown("---")
st.markdown("<p style='text-align: center; color: #666;'>© 2026 Developed by Apichai | Senior Piping Engineer & Trader</p>", unsafe_allow_html=True)
