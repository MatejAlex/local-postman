'use client';

import { useState } from 'react';
import type { ApiResponse } from '../lib/types';
import { formatSize, formatTime, prettyJson, prettyMarkup, statusColor } from '../lib/utils';

interface Props {
  response: ApiResponse | null;
  isSending: boolean;
}

type Tab = 'preview' | 'pretty' | 'raw' | 'headers';

export default function ResponseViewer({ response, isSending }: Props) {
  // Tied to the response it was picked for, so every new response opens on its own default.
  const [chosenTab, setChosenTab] = useState<{ of: ApiResponse | null; tab: Tab } | null>(null);

  const body = response?.body ?? '';
  const contentType = response?.contentType ?? '';
  const isHtml = looksHtml(contentType, body);

  // An HTML page is unreadable as source, so it opens on the rendered preview instead.
  const defaultTab: Tab = isHtml ? 'preview' : 'pretty';
  const tab = chosenTab?.of === response ? chosenTab.tab : defaultTab;
  const setTab = (next: Tab) => setChosenTab({ of: response, tab: next });

  if (isSending) {
    return (
      <div className="flex items-center justify-center h-full text-sm text-[var(--muted-fg)]">
        Sending request…
      </div>
    );
  }

  if (!response) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2 text-[var(--muted-fg)]">
        <span className="text-3xl">↘</span>
        <p className="text-sm">Send a request to see the response.</p>
      </div>
    );
  }

  if (response.error) {
    return (
      <div className="p-4">
        <div className="flex items-center gap-2 mb-2 text-[var(--danger)] text-sm font-medium">
          <span className="w-2 h-2 rounded-full bg-[var(--danger)]" /> Request failed
        </div>
        <pre className="text-sm text-[var(--danger)] whitespace-pre-wrap font-mono">{response.error}</pre>
      </div>
    );
  }

  const headerEntries = Object.entries(response.headers);
  const tabs: Tab[] = isHtml ? ['preview', 'pretty', 'raw', 'headers'] : ['pretty', 'raw', 'headers'];

  return (
    <div className="flex flex-col h-full">
      {/* Status bar */}
      <div className="flex items-center gap-4 px-4 py-2 border-b border-[var(--border)] text-sm">
        <span className="font-semibold" style={{ color: statusColor(response.status) }}>
          {response.status} {response.statusText}
        </span>
        <span className="text-[var(--muted-fg)]">{formatTime(response.timeMs)}</span>
        <span className="text-[var(--muted-fg)]">{formatSize(response.sizeBytes)}</span>
        <button
          onClick={() => navigator.clipboard?.writeText(response.body)}
          className="ml-auto px-2 py-1 text-xs text-[var(--muted-fg)] hover:text-[var(--fg)]"
        >
          Copy
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 px-4 border-b border-[var(--border)]">
        {tabs.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm capitalize border-b-2 -mb-px transition-colors ${
              tab === t
                ? 'border-[var(--accent)] text-[var(--fg)]'
                : 'border-transparent text-[var(--muted-fg)] hover:text-[var(--fg)]'
            }`}
          >
            {t === 'headers' ? `Headers (${headerEntries.length})` : t}
          </button>
        ))}
      </div>

      {/* Content */}
      {tab === 'preview' ? (
        <iframe
          // No allow-scripts and no allow-same-origin: the page renders, but cannot run.
          sandbox=""
          srcDoc={response.body}
          title="Rendered response"
          className="flex-1 w-full bg-white border-0"
        />
      ) : (
        <div className="flex-1 overflow-auto p-4">
          {tab === 'headers' ? (
            <div className="flex flex-col gap-1 font-mono text-xs">
              {headerEntries.map(([k, v]) => (
                <div key={k} className="flex gap-2 py-1 border-b border-[var(--border)]">
                  <span className="text-[var(--accent)] shrink-0">{k}:</span>
                  <span className="text-[var(--fg)] break-all">{v}</span>
                </div>
              ))}
            </div>
          ) : (
            <pre className="text-sm font-mono whitespace-pre-wrap break-words text-[var(--fg)]">
              {tab === 'pretty' ? prettyBody(response) : response.body || '(empty body)'}
            </pre>
          )}
        </div>
      )}
    </div>
  );
}

/** Indent whatever the body turns out to be; anything unrecognised is shown as it arrived. */
function prettyBody(response: ApiResponse): string {
  const { body, contentType } = response;
  if (body.trim() === '') {
    return '(empty body)';
  }
  if (looksHtml(contentType, body) || looksXml(contentType, body)) {
    return prettyMarkup(body);
  }
  if (contentType.includes('json') || looksJson(body)) {
    return prettyJson(body);
  }
  return body;
}

function looksJson(body: string): boolean {
  const t = body.trim();
  return t.startsWith('{') || t.startsWith('[');
}

function looksHtml(contentType: string, body: string): boolean {
  if (contentType.includes('html')) {
    return true;
  }
  const head = body.trimStart().slice(0, 100).toLowerCase();
  return head.startsWith('<!doctype html') || head.startsWith('<html');
}

function looksXml(contentType: string, body: string): boolean {
  if (contentType.includes('xml')) {
    return true;
  }
  return body.trimStart().startsWith('<?xml');
}
