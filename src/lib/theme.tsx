'use client';

import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

// Three modes per global standard. Rotation: dark-grey -> dark -> light -> dark-grey.
export type ThemeMode = 'dark-grey' | 'dark' | 'light';

const ORDER: ThemeMode[] = ['dark-grey', 'dark', 'light'];
const STORAGE_KEY = 'local-postman-theme';

interface ThemeContextValue {
  mode: ThemeMode;
  cycle: () => void;
}

const ThemeContext = createContext<ThemeContextValue>({ mode: 'dark-grey', cycle: () => {} });

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<ThemeMode>('dark-grey');

  // Hydrate from localStorage after mount. Reading during render/lazy-init would
  // diverge from the server-rendered default and mismatch hydration on the theme icon.
  useEffect(() => {
    const saved = localStorage.getItem(STORAGE_KEY) as ThemeMode | null;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (saved && ORDER.includes(saved)) setMode(saved);
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    root.classList.remove('theme-dark-grey', 'theme-dark', 'theme-light');
    root.classList.add(`theme-${mode}`);
    localStorage.setItem(STORAGE_KEY, mode);
  }, [mode]);

  const cycle = () => setMode((m) => ORDER[(ORDER.indexOf(m) + 1) % ORDER.length]);

  return <ThemeContext.Provider value={{ mode, cycle }}>{children}</ThemeContext.Provider>;
}

export const useTheme = () => useContext(ThemeContext);
