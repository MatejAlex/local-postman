'use client';

import { useState } from 'react';
import type { ApiRequest, BodyType, CollectionAuth, Method, RequestAuthMode } from '../lib/types';
import { METHODS, mcpConfigOf, requestAuthOf, requestKindOf } from '../lib/types';
import type { McpMethod } from '../lib/mcp';
import { MCP_METHODS, MCP_TARGET_LABEL, mcpNeedsTarget, mcpTakesArguments } from '../lib/mcp';
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

type Tab = 'params' | 'auth' | 'headers' | 'body' | 'mcp';

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
  mcp: 'MCP',
};

// An MCP call has no query params and no body of its own, so those two tabs
// would only ever be empty. Fewer tabs is the point.
const HTTP_TABS: Tab[] = ['params', 'auth', 'headers', 'body'];
const MCP_TABS: Tab[] = ['mcp', 'auth', 'headers'];

export default function RequestBuilder({
  request,
  onChange,
  onSend,
  isSending,
  collectionAuth,
  vars,
}: Props) {
  const isMcp = requestKindOf(request) === 'mcp';
  const tabs = isMcp ? MCP_TABS : HTTP_TABS;
  const [tab, setTab] = useState<Tab>(tabs[0]);

  const patch = (p: Partial<ApiRequest>) => onChange({ ...request, ...p });
  const auth = requestAuthOf(request);
  const mcp = mcpConfigOf(request);
  const patchMcp = (p: Partial<typeof mcp>) => patch({ mcp: { ...mcp, ...p } });

  // Switching request kind can leave the old tab selected and showing nothing.
  const activeTab = tabs.includes(tab) ? tab : tabs[0];

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
        {isMcp ? (
          <span
            className="px-2 py-2 text-sm font-semibold rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] method-MCP"
            title="MCP over Streamable HTTP. The transport is a POST; the session handshake is handled for you."
          >
            MCP
          </span>
        ) : (
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
        )}
        <input
          value={request.url}
          onChange={(e) => patch({ url: e.target.value })}
          onKeyDown={(e) => e.key === 'Enter' && canSend && onSend()}
          placeholder={isMcp ? 'http://localhost:8000/mcp' : 'https://api.example.com/{{path}}'}
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
        {tabs.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm border-b-2 -mb-px transition-colors ${
              activeTab === t
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
        {activeTab === 'mcp' && (
          <McpPanel config={mcp} onChange={patchMcp} />
        )}
        {activeTab === 'params' && (
          <KeyValueEditor rows={request.params} onChange={(params) => patch({ params })} />
        )}
        {activeTab === 'auth' && (
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
        {activeTab === 'headers' && (
          <KeyValueEditor
            rows={request.headers}
            onChange={(headers) => patch({ headers })}
            keyPlaceholder="Header"
          />
        )}
        {activeTab === 'body' && (
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

/**
 * The whole MCP surface: which call, what it targets, and its arguments.
 *
 * Deliberately not here: connecting is not a step (every send opens and closes
 * its own session), there is no OAuth dance, and no server is launched for you.
 * Those are the three things that make the reference inspector a mode you enter
 * rather than a request you send.
 */
function McpPanel({
  config,
  onChange,
}: {
  config: { method: McpMethod; target: string; args: string };
  onChange: (patch: Partial<{ method: McpMethod; target: string; args: string }>) => void;
}) {
  const targetLabel = MCP_TARGET_LABEL[config.method];
  const takesArgs = mcpTakesArguments(config.method);

  return (
    <div className="flex flex-col gap-4 max-w-2xl">
      <label className="flex flex-col gap-1.5">
        <span className="text-xs text-[var(--muted-fg)]">Method</span>
        <select
          value={config.method}
          onChange={(e) => onChange({ method: e.target.value as McpMethod })}
          className="px-3 py-2 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono cursor-pointer"
        >
          {MCP_METHODS.map((m) => (
            <option key={m} value={m} className="text-[var(--fg)] bg-[var(--bg-elev)]">
              {m}
            </option>
          ))}
        </select>
      </label>

      {mcpNeedsTarget(config.method) && (
        <label className="flex flex-col gap-1.5">
          <span className="text-xs text-[var(--muted-fg)]">{targetLabel}</span>
          <input
            value={config.target}
            onChange={(e) => onChange({ target: e.target.value })}
            placeholder={config.method === 'resources/read' ? 'file:///…' : 'read_document'}
            className="px-3 py-2 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono"
          />
        </label>
      )}

      {takesArgs && (
        <label className="flex flex-col gap-1.5">
          <span className="flex items-center text-xs text-[var(--muted-fg)]">
            Arguments (JSON)
            <button
              onClick={() => onChange({ args: prettyJson(config.args) })}
              className="ml-auto px-2 py-0.5 text-xs text-[var(--muted-fg)] hover:text-[var(--fg)]"
            >
              Beautify
            </button>
          </span>
          <textarea
            value={config.args}
            onChange={(e) => onChange({ args: e.target.value })}
            placeholder={'{\n  "query": "{{search}}"\n}'}
            spellCheck={false}
            rows={8}
            className="w-full p-3 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none font-mono resize-none"
          />
        </label>
      )}

      <p className="text-xs text-[var(--muted-fg)]">
        {takesArgs
          ? 'Run the matching list method first to see the exact argument names. {{variables}} work here too.'
          : 'Takes no arguments. Send it to see what this server offers.'}
      </p>
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
