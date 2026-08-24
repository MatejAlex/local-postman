'use client';

import { useState } from 'react';
import type { ApiRequest, BodyType, CollectionAuth, Method, RequestAuthMode } from '../lib/types';
import { METHODS, requestAuthOf } from '../lib/types';
import { prettyJson } from '../lib/utils';
import KeyValueEditor from './KeyValueEditor';
import BasicAuthFields from './BasicAuthFields';

interface Props {
  request: ApiRequest;
  onChange: (request: ApiRequest) => void;
  onSend: () => void;
  isSending: boolean;
  collectionAuth: CollectionAuth | null;
  vars: Record<string, string>;
}

type Tab = 'params' | 'auth' | 'headers' | 'body';

const BODY_TYPES: BodyType[] = ['none', 'json', 'raw'];

const AUTH_MODES: { value: RequestAuthMode; label: string }[] = [
  { value: 'inherit', label: 'Inherit' },
  { value: 'basic', label: 'Basic' },
  { value: 'none', label: 'No auth' },
];

const TAB_LABELS: Record<Tab, string> = {
  params: 'Params',
  auth: 'Auth',
  headers: 'Headers',
  body: 'Body',
};

export default function RequestBuilder({
  request,
  onChange,
  onSend,
  isSending,
  collectionAuth,
  vars,
}: Props) {
  const [tab, setTab] = useState<Tab>('params');

  const patch = (p: Partial<ApiRequest>) => onChange({ ...request, ...p });
  const auth = requestAuthOf(request);

  const count = (n: number) => (n > 0 ? <span className="ml-1.5 text-xs text-[var(--accent)]">{n}</span> : null);
  const activeParams = request.params.filter((p) => p.enabled && p.key.trim()).length;
  const activeHeaders = request.headers.filter((h) => h.enabled && h.key.trim()).length;

  const inheritsBasic = auth.mode === 'inherit' && collectionAuth?.mode === 'basic';
  const authActive = auth.mode === 'basic' || inheritsBasic;

  const canSend = request.url.trim().length > 0 && !isSending;

  return (
    <div className="flex flex-col h-full">
      {/* Name */}
      <input
        value={request.name}
        onChange={(e) => patch({ name: e.target.value })}
        className="px-4 pt-4 pb-2 bg-transparent text-base font-medium outline-none text-[var(--fg)] placeholder:text-[var(--muted-fg)]"
        placeholder="Request name"
      />

      {/* URL bar */}
      <div className="flex items-center gap-2 px-4 pb-3">
        <select
          value={request.method}
          onChange={(e) => patch({ method: e.target.value as Method })}
          className={`px-2 py-2 text-sm font-semibold rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] outline-none cursor-pointer method-${request.method}`}
        >
          {METHODS.map((m) => (
            <option key={m} value={m} className="text-[var(--fg)] bg-[var(--bg-elev)]">
              {m}
            </option>
          ))}
        </select>
        <input
          value={request.url}
          onChange={(e) => patch({ url: e.target.value })}
          onKeyDown={(e) => e.key === 'Enter' && canSend && onSend()}
          placeholder="https://api.example.com/{{path}}"
          className="flex-1 px-3 py-2 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
        />
        <button
          onClick={onSend}
          disabled={!canSend}
          className="px-5 py-2 text-sm font-semibold rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:opacity-90 disabled:opacity-40 transition-opacity"
        >
          {isSending ? 'Sending…' : 'Send'}
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 px-4 border-b border-[var(--border)]">
        {(['params', 'auth', 'headers', 'body'] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm border-b-2 -mb-px transition-colors ${
              tab === t
                ? 'border-[var(--accent)] text-[var(--fg)]'
                : 'border-transparent text-[var(--muted-fg)] hover:text-[var(--fg)]'
            }`}
          >
            {TAB_LABELS[t]}
            {t === 'params' && count(activeParams)}
            {t === 'headers' && count(activeHeaders)}
            {t === 'auth' && authActive && <span className="ml-1.5 text-[var(--accent)]">●</span>}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-auto p-4">
        {tab === 'params' && (
          <KeyValueEditor rows={request.params} onChange={(params) => patch({ params })} />
        )}
        {tab === 'auth' && (
          <div className="flex flex-col gap-4 max-w-xl">
            <div className="flex items-center gap-2">
              {AUTH_MODES.map((m) => (
                <button
                  key={m.value}
                  onClick={() => patch({ auth: { ...auth, mode: m.value } })}
                  className={`px-3 py-1 text-xs rounded-md border transition-colors ${
                    auth.mode === m.value
                      ? 'border-[var(--accent)] text-[var(--accent)] bg-[var(--accent-soft)]'
                      : 'border-[var(--border)] text-[var(--muted-fg)] hover:text-[var(--fg)]'
                  }`}
                >
                  {m.label}
                </button>
              ))}
            </div>

            {auth.mode === 'inherit' && <InheritNote collectionAuth={collectionAuth} />}

            {auth.mode === 'basic' && (
              <BasicAuthFields
                value={auth.basic}
                onChange={(basic) => patch({ auth: { ...auth, basic } })}
                vars={vars}
              />
            )}

            {auth.mode === 'none' && (
              <p className="text-sm text-[var(--muted-fg)]">
                No Authorization header is sent, even when the collection sets one.
              </p>
            )}
          </div>
        )}
        {tab === 'headers' && (
          <KeyValueEditor
            rows={request.headers}
            onChange={(headers) => patch({ headers })}
            keyPlaceholder="Header"
          />
        )}
        {tab === 'body' && (
          <div className="flex flex-col gap-3 h-full">
            <div className="flex items-center gap-2">
              {BODY_TYPES.map((bt) => (
                <button
                  key={bt}
                  onClick={() => patch({ bodyType: bt })}
                  className={`px-3 py-1 text-xs rounded-md border transition-colors ${
                    request.bodyType === bt
                      ? 'border-[var(--accent)] text-[var(--accent)] bg-[var(--accent-soft)]'
                      : 'border-[var(--border)] text-[var(--muted-fg)] hover:text-[var(--fg)]'
                  }`}
                >
                  {bt === 'none' ? 'None' : bt === 'json' ? 'JSON' : 'Raw'}
                </button>
              ))}
              {request.bodyType === 'json' && (
                <button
                  onClick={() => patch({ body: prettyJson(request.body) })}
                  className="ml-auto px-2 py-1 text-xs text-[var(--muted-fg)] hover:text-[var(--fg)]"
                >
                  Beautify
                </button>
              )}
            </div>
            {request.bodyType === 'none' ? (
              <p className="text-sm text-[var(--muted-fg)]">This request has no body.</p>
            ) : (
              <textarea
                value={request.body}
                onChange={(e) => patch({ body: e.target.value })}
                placeholder={request.bodyType === 'json' ? '{\n  "key": "value"\n}' : 'Raw body…'}
                spellCheck={false}
                className="flex-1 min-h-48 w-full p-3 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono resize-none"
              />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function InheritNote({ collectionAuth }: { collectionAuth: CollectionAuth | null }) {
  if (!collectionAuth || collectionAuth.mode !== 'basic') {
    return (
      <p className="text-sm text-[var(--muted-fg)]">
        This collection has no auth set, so this request sends none. Set it on the collection to
        cover every request at once.
      </p>
    );
  }

  const who = collectionAuth.basic.username.trim();
  return (
    <p className="text-sm text-[var(--muted-fg)]">
      Using the collection&rsquo;s Basic auth
      {who ? (
        <>
          {' as '}
          <code className="font-mono text-[var(--fg)]">{who}</code>
        </>
      ) : null}
      {collectionAuth.basic.base64 ? '.' : ', sent unencoded.'}
    </p>
  );
}
