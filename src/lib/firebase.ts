import { initializeApp } from 'firebase/app'
import { getAuth, GoogleAuthProvider } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: "AIzaSyBnUg0_h_sH9WmmUn6ld7HXF_QKF1quq78",
  authDomain: "dca-calculator-abaa1.firebaseapp.com",
  projectId: "dca-calculator-abaa1",
  storageBucket: "dca-calculator-abaa1.firebasestorage.app",
  messagingSenderId: "188338284439",
  appId: "1:188338284439:web:94bf00fd50696c94d106d2",
  measurementId: "G-NLCC74HE08"
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app)
export const googleProvider = new GoogleAuthProvider()
