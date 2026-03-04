import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Guard against duplicate createRoot calls during HMR
const container = document.getElementById('root')!;
if (!(container as any)._reactRoot) {
  const root = createRoot(container);
  (container as any)._reactRoot = root;
  root.render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
} else {
  (container as any)._reactRoot.render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
