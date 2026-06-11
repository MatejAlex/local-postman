'use client';

import type { KeyValue } from '../lib/types';

interface Props {
  rows: KeyValue[];
  onChange: (rows: KeyValue[]) => void;
  keyPlaceholder?: string;
  valuePlaceholder?: string;
}

// A reusable editor for key/value pairs (query params, headers, env variables).
// Always renders one trailing blank row; typing into it materialises a new row.
export default function KeyValueEditor({
  rows,
  onChange,
  keyPlaceholder = 'Key',
  valuePlaceholder = 'Value',
}: Props) {
  const display = [...rows, { key: '', value: '', enabled: true }];

  const nonEmpty = (r: KeyValue) => r.key.trim() !== '' || r.value.trim() !== '';

  const update = (index: number, patch: Partial<KeyValue>) => {
    onChange(display.map((r, i) => (i === index ? { ...r, ...patch } : r)).filter(nonEmpty));
  };

  const remove = (index: number) => {
    onChange(display.filter((_, i) => i !== index).filter(nonEmpty));
  };

  return (
    <div className="flex flex-col gap-1">
      {display.map((row, i) => {
        const isBlank = i === display.length - 1;
        return (
          <div key={i} className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={row.enabled}
              onChange={(e) => update(i, { enabled: e.target.checked })}
              className="accent-[var(--accent)] cursor-pointer"
              style={{ opacity: isBlank ? 0.3 : 1 }}
              aria-label="Enabled"
            />
            <input
              value={row.key}
              onChange={(e) => update(i, { key: e.target.value })}
              placeholder={keyPlaceholder}
              className="flex-1 px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
            />
            <input
              value={row.value}
              onChange={(e) => update(i, { value: e.target.value })}
              placeholder={valuePlaceholder}
              className="flex-1 px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
            />
            <button
              onClick={() => remove(i)}
              disabled={isBlank}
              className="w-7 h-7 shrink-0 rounded-md text-[var(--muted-fg)] hover:text-[var(--danger)] hover:bg-[var(--hover)] disabled:opacity-0 transition-colors"
              aria-label="Remove row"
            >
              ✕
            </button>
          </div>
        );
      })}
    </div>
  );
}
