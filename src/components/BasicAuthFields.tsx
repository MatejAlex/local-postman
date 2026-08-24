'use client';

import { useState } from 'react';
import type { BasicAuth } from '../lib/types';
import { basicAuthHeader } from '../lib/utils';

interface Props {
  value: BasicAuth;
  onChange: (basic: BasicAuth) => void;
  vars: Record<string, string>;
}

// Username/password editor shared by the collection modal and the request Auth tab.
export default function BasicAuthFields({ value, onChange, vars }: Props) {
  const [reveal, setReveal] = useState(false);

  const patch = (p: Partial<BasicAuth>) => onChange({ ...value, ...p });

  const header = basicAuthHeader(value, vars);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-1">
        <label className="text-xs text-[var(--muted-fg)]">Username</label>
        <input
          value={value.username}
          onChange={(e) => patch({ username: e.target.value })}
          placeholder="user or {{db_user}}"
          autoComplete="off"
          spellCheck={false}
          className="px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
        />
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-xs text-[var(--muted-fg)]">Password</label>
        <div className="flex items-center gap-2">
          <input
            type={reveal ? 'text' : 'password'}
            value={value.password}
            onChange={(e) => patch({ password: e.target.value })}
            placeholder="password or {{db_password}}"
            autoComplete="off"
            spellCheck={false}
            className="flex-1 px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
          />
          <button
            onClick={() => setReveal((v) => !v)}
            className="px-2 py-1.5 text-xs rounded-md text-[var(--muted-fg)] hover:text-[var(--fg)] hover:bg-[var(--hover)]"
            title={reveal ? 'Hide' : 'Show'}
          >
            {reveal ? 'Hide' : 'Show'}
          </button>
        </div>
      </div>

      <label className="flex items-start gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={value.base64}
          onChange={(e) => patch({ base64: e.target.checked })}
          className="mt-0.5 accent-[var(--accent)] cursor-pointer"
        />
        <span className="text-sm">
          Base64 encode credentials
          <span className="block text-xs text-[var(--muted-fg)]">
            Standard HTTP Basic, and what ORDS expects. Leave this on unless you are debugging.
          </span>
        </span>
      </label>

      {!value.base64 && (
        <p className="text-xs text-[var(--warn)]">
          Credentials will be sent verbatim. This is not valid HTTP Basic and most servers will
          reject it.
        </p>
      )}

      <div className="flex flex-col gap-1">
        <span className="text-xs text-[var(--muted-fg)]">Header sent</span>
        <code className="px-2 py-1.5 text-xs rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] font-mono break-all text-[var(--muted-fg)]">
          {header === null
            ? 'None — fill in a username or password.'
            : reveal
              ? `Authorization: ${header}`
              : 'Authorization: Basic ••••••••  (Show to reveal)'}
        </code>
      </div>
    </div>
  );
}
