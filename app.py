import streamlit as st
import yfinance as yf
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime

# --- 1. การตั้งค่าหน้าเว็บและ Style ---
st.set_page_config(page_title="Professional DCA Tool", layout="wide")

# ใช้ CSS เพื่อปรับแต่งให้เหมือนในตัวอย่าง
st.markdown("""
    <style>
    /* 1. พื้นหลังดำสนิทแบบ Netflix */
    .main {
        background-color: #000000;
    }
    
    /* 2. ปรับแต่ง Metric Cards ให้ดูพรีเมียม */
    [data-testid="stMetric"] {
        background-color: #141414 !important;
        border: 1px solid #333333 !important;
        border-radius: 8px !important;
        padding: 15px !important;
        box-shadow: 0 4px 6px rgba(0,0,0,0.3) !important;
    }
    
    /* 3. ส่วนหัวของผลลัพธ์หลัก */
    .main-result {
        background-color: #141414 !important;
        border-radius: 12px !important;
        padding: 30px !important;
        border: 1px solid #E50914 !important; /* ขอบสีแดง Netflix */
    }

    /* 4. สีข้อความและหัวข้อ */
    h1, h2, h3, .stMarkdown p {
        color: #FFFFFF !important;
    }
    
    .main-result h1 {
        color: #E50914 !important; /* หัวข้อกำไร/ขาดทุนเป็นสีแดง */
    }

    /* 5. ปรับแต่งปุ่มกดให้เป็นสีแดง Netflix */
    div.stButton > button {
        background-color: #E50914 !important;
        color: white !important;
        border: none !important;
        border-radius: 4px !important;
        font-weight: bold !important;
        transition: 0.3s !important;
    }
    
    div.stButton > button:hover {
        background-color: #B20710 !important;
        transform: scale(1.05);
    }

    /* 6. ปรับสี Input (ช่องกรอกข้อมูล) ให้เข้ากับธีมมืด */
    .stTextInput input, .stNumberInput input {
        background-color: #2F2F2F !important;
        color: white !important;
        border: 1px solid #444 !important;
    }
    </style>
    """, unsafe_allow_html=True)

# --- 2. ส่วนหัวของเว็บไซต์ ---
st.markdown("<div style='text-align: center;'>", unsafe_allow_html=True)
st.title("🎯 เครื่องคำนวณ DCA")
st.write("วางแผนการลงทุนแบบถัวเฉลี่ย เพื่อดูการเติบโตของพอร์ตในระยะยาว")
st.markdown("</div>", unsafe_allow_html=True)

# --- 3. ส่วนรับข้อมูล (จัดวางแนวนอนเหมือนตัวอย่าง) ---
with st.container(border=True):
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        ticker = st.text_input("ชื่อหุ้น/คริปโต", value="NVDA").upper()
    with col2:
        monthly_investment = st.number_input("เงินลงทุนต่อเดือน", min_value=0, value=5000)
    with col3:
        start_date = st.date_input("วันที่เริ่มลงทุน", value=datetime(2023, 1, 1))
    with col4:
        st.write("") # เว้นวรรค
        run_button = st.button("🚀 คำนวณผลลัพธ์", use_container_width=True)

# --- 4. ส่วนประมวลผลและแสดงผล ---
if run_button:
    with st.spinner('กำลังประมวลผลข้อมูล...'):
        data = yf.download(ticker, start=start_date, progress=False)
        
        if not data.empty:
            # Logic การคำนวณ
            monthly_data = data['Close'].resample('MS').first().dropna()
            dca_df = pd.DataFrame(index=monthly_data.index)
            dca_df['Price'] = monthly_data.values
            dca_df['Shares'] = monthly_investment / dca_df['Price']
            dca_df['Total_Shares'] = dca_df['Shares'].cumsum()
            dca_df['Invested'] = [monthly_investment * i for i in range(1, len(dca_df)+1)]
            dca_df['Value'] = dca_df['Total_Shares'] * dca_df['Price']
            
            total_invested = dca_df['Invested'].iloc[-1]
            current_value = dca_df['Value'].iloc[-1]
            profit = current_value - total_invested
            roi = (profit / total_invested) * 100

            # แสดงผลลัพธ์ตัวเลขใหญ่ๆ ตรงกลาง (เหมือนในรูป)
            st.markdown(f"""
                <div class="main-result">
                    <p style="margin-bottom:0; color:#666;">มูลค่าพอร์ตโดยประมาณ</p>
                    <h1>฿{current_value:,.2f}</h1>
                </div>
                """, unsafe_allow_html=True)

            # การ์ดสรุปผล 2 ข้าง
            res_col1, res_col2 = st.columns(2)
            res_col1.metric("เงินต้นทั้งหมด", f"฿{total_invested:,.2f}")
            res_col2.metric("กำไร/ขาดทุน", f"฿{profit:,.2f}", f"{roi:.2f}%")

            # กราฟการเติบโต
            st.markdown("### 📈 กราฟแสดงการเติบโตของพอร์ต")
            fig = go.Figure()
            fig.add_trace(go.Scatter(x=dca_df.index, y=dca_df['Invested'], name="เงินต้น", line=dict(color='#cbd5e1', dash='dash')))
            fig.add_trace(go.Scatter(x=dca_df.index, y=dca_df['Value'], name="มูลค่าพอร์ต", fill='tozeroy', line=dict(color='#6366f1', width=4)))
            fig.update_layout(hovermode="x unified", template="plotly_white", height=400)
            st.plotly_chart(fig, use_container_width=True)

            # ส่วนข้อมูลเพิ่มเติมด้านล่าง
            tab1, tab2 = st.tabs(["📝 วิธีการใช้งาน", "📚 DCA คืออะไร?"])
            with tab1:
                st.write("1. ใส่ชื่อหุ้นที่ต้องการ (เช่น PTT.BK สำหรับหุ้นไทย หรือ NVDA สำหรับหุ้นนอก)")
                st.write("2. กำหนดจำนวนเงินที่จะลงทุนเท่ากันทุกเดือน")
                st.write("3. เลือกวันที่เริ่มต้น แล้วกดปุ่มคำนวณเพื่อดูผลตอบแทนย้อนหลัง")
            with tab2:
                st.info("DCA (Dollar-Cost Averaging) คือการลงทุนแบบสม่ำเสมอด้วยจำนวนเงินที่เท่ากัน โดยไม่สนใจราคาหุ้น ณ ขณะนั้น เพื่อลดความเสี่ยงจากความผันผวนของตลาด")
        else:
            st.error("⚠️ ไม่พบข้อมูลหุ้น โปรดตรวจสอบชื่อ Ticker อีกครั้ง")

# ฟุตเตอร์
st.markdown("---")
st.markdown("<p style='text-align: center; color: #999;'>© 2026 Developed by Apichai | Engineering Financial Tools</p>", unsafe_allow_html=True)
