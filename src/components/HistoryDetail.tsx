'use client';

import { useEffect, useState } from 'react';
import type { HistoryItem } from '../lib/types';
import { prettyJson, statusColor } from '../lib/utils';
import ResponseViewer from './ResponseViewer';

interface Props {
  item: HistoryItem;
  onReplay: (item: HistoryItem) => void;
  onClose: () => void;
}

type Pane = 'response' | 'request';

export default function HistoryDetail({ item, onReplay, onClose }: Props) {
  const [pane, setPane] = useState<Pane>('response');

  useEffect(() => {
    const closeOnEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
      onClick={onClose}
    >
      <div
        className="w-full max-w-4xl h-[82vh] flex flex-col overflow-hidden rounded-lg border border-[var(--border)] bg-[var(--bg-elev)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Title */}
        <div className="flex items-start gap-3 px-4 py-3 border-b border-[var(--border)]">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className={`text-xs font-bold method-${badge(item)}`}>{badge(item)}</span>
              <span className="text-sm font-medium truncate">
                {item.name?.trim() || <span className="text-[var(--muted-fg)] italic">Unnamed request</span>}
              </span>
              {item.response.error ? (
                <span className="text-xs font-semibold text-[var(--danger)]">ERR</span>
              ) : (
                <span
                  className="text-xs font-semibold"
                  style={{ color: statusColor(item.response.status) }}
                >
                  {item.response.status}
                </span>
              )}
              <span className="text-xs text-[var(--muted-fg)]">
                {new Date(item.timestamp).toLocaleString()}
              </span>
            </div>
            <div className="mt-1 text-xs font-mono text-[var(--muted-fg)] break-all">{item.url}</div>
          </div>
          <button
            onClick={() => onReplay(item)}
            className="px-2.5 py-1 text-xs rounded-md bg-[var(--bg-elev-2)] text-[var(--fg)] hover:bg-[var(--hover)]"
          >
            ↻ Send again
          </button>
          <button
            onClick={onClose}
            aria-label="Close"
            className="w-7 h-7 shrink-0 flex items-center justify-center rounded-md text-[var(--muted-fg)] hover:text-[var(--fg)] hover:bg-[var(--hover)]"
          >
            ✕
          </button>
        </div>

        {/* Panes */}
        <div className="flex gap-1 px-4 border-b border-[var(--border)]">
          {(['response', 'request'] as Pane[]).map((p) => (
            <button
              key={p}
              onClick={() => setPane(p)}
              className={`px-3 py-2 text-sm capitalize border-b-2 -mb-px transition-colors ${
                pane === p
                  ? 'border-[var(--accent)] text-[var(--fg)]'
                  : 'border-transparent text-[var(--muted-fg)] hover:text-[var(--fg)]'
              }`}
            >
              {p}
            </button>
          ))}
        </div>

        <div className="flex-1 overflow-hidden">
          {pane === 'response' ? (
            <ResponseViewer response={item.response} isSending={false} />
          ) : (
            <SentRequest item={item} />
          )}
        </div>
      </div>
    </div>
  );
}

/** What actually went out: variables already substituted, auth already resolved. */
function SentRequest({ item }: { item: HistoryItem }) {
  const headerEntries = Object.entries(item.resolved.headers);
  const body = item.resolved.body ?? '';

  return (
    <div className="h-full overflow-auto p-4 flex flex-col gap-4">
      <Section label="URL">
        <p className="font-mono text-xs break-all text-[var(--fg)]">{item.resolved.url}</p>
      </Section>

      <Section label={`Headers (${headerEntries.length})`}>
        {headerEntries.length === 0 ? (
          <p className="text-xs text-[var(--muted-fg)]">No headers sent.</p>
        ) : (
          <div className="flex flex-col gap-1 font-mono text-xs">
            {headerEntries.map(([key, value]) => (
              <div key={key} className="flex gap-2 py-1 border-b border-[var(--border)]">
                <span className="text-[var(--accent)] shrink-0">{key}:</span>
                <span className="text-[var(--fg)] break-all">{value}</span>
              </div>
            ))}
          </div>
        )}
      </Section>

      <Section label="Body">
        <pre className="text-xs font-mono whitespace-pre-wrap break-words text-[var(--fg)]">
          {body.trim() === '' ? '(no body)' : prettyJson(body)}
        </pre>
      </Section>
    </div>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)]">
        {label}
      </span>
      {children}
    </div>
  );
}

/** A replayed MCP call is a POST on the wire; the badge must not say so. */
function badge(item: HistoryItem): string {
  return item.resolved.mcp ? 'MCP' : item.method;
}
