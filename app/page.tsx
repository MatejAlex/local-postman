'use client';

import { useEffect, useRef, useState } from 'react';
import type {
  ApiRequest,
  ApiResponse,
  Environment,
  HistoryItem,
  RequestGroup,
} from '../src/lib/types';
import { APP_VERSION, newGroup, newRequest } from '../src/lib/types';
import { resolveRequest } from '../src/lib/utils';
import {
  appendHistory,
  clearHistory,
  deleteEnvironment,
  deleteGroup,
  loadAll,
  saveEnvironment,
  saveGroup,
  sendResolved,
} from '../src/lib/storage';
import { useTheme } from '../src/lib/theme';
import Sidebar from '../src/components/Sidebar';
import RequestBuilder from '../src/components/RequestBuilder';
import ResponseViewer from '../src/components/ResponseViewer';
import HistoryPanel from '../src/components/HistoryPanel';

export default function Home() {
  const [environments, setEnvironments] = useState<Environment[]>([]);
  const [groups, setGroups] = useState<RequestGroup[]>([]);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [activeEnvId, setActiveEnvId] = useState<string | null>(null);
  const [activeRequest, setActiveRequest] = useState<ApiRequest | null>(null);
  const [response, setResponse] = useState<ApiResponse | null>(null);
  const [isSending, setIsSending] = useState(false);
  const [showHistory, setShowHistory] = useState(true);
  const [loaded, setLoaded] = useState(false);

  const saveTimers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  useEffect(() => {
    loadAll().then((snap) => {
      setEnvironments(snap.environments);
      setGroups(snap.groups);
      setHistory(snap.history);
      if (snap.environments[0]) setActiveEnvId(snap.environments[0].id);
      setLoaded(true);
    });
  }, []);

  const activeEnv = environments.find((e) => e.id === activeEnvId) ?? null;

  // Persist a group, debounced per-group so rapid edits collapse into one write.
  const queueSaveGroup = (group: RequestGroup) => {
    clearTimeout(saveTimers.current[group.id]);
    saveTimers.current[group.id] = setTimeout(() => saveGroup(group), 400);
  };

  // ---- Request editing ----
  const handleRequestChange = (updated: ApiRequest) => {
    setActiveRequest(updated);
    let touched: RequestGroup | undefined;
    setGroups((prev) =>
      prev.map((g) => {
        if (!g.requests.some((r) => r.id === updated.id)) return g;
        touched = { ...g, requests: g.requests.map((r) => (r.id === updated.id ? updated : r)) };
        return touched;
      })
    );
    if (touched) queueSaveGroup(touched);
  };

  // ---- Send ----
  const handleSend = async () => {
    if (!activeRequest) return;
    setIsSending(true);
    setResponse(null);
    const resolved = resolveRequest(activeRequest, activeEnv);
    const resp = await sendResolved(resolved);
    setResponse(resp);
    setIsSending(false);

    const item: HistoryItem = {
      id: `h-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      timestamp: Date.now(),
      method: activeRequest.method,
      url: resolved.url,
      resolved,
      response: resp,
    };
    setHistory((prev) => [item, ...prev].slice(0, 50));
    appendHistory(item, history);
  };

  const handleReplay = async (item: HistoryItem) => {
    setIsSending(true);
    setResponse(null);
    const resp = await sendResolved(item.resolved);
    setResponse(resp);
    setIsSending(false);
    const replayed: HistoryItem = {
      ...item,
      id: `h-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      timestamp: Date.now(),
      response: resp,
    };
    setHistory((prev) => [replayed, ...prev].slice(0, 50));
    appendHistory(replayed, history);
  };

  // ---- Groups ----
  const handleAddGroup = () => {
    const g = newGroup();
    setGroups((prev) => [...prev, g]);
    saveGroup(g);
  };

  const handleRenameGroup = (id: string, name: string) => {
    let touched: RequestGroup | undefined;
    setGroups((prev) =>
      prev.map((g) => {
        if (g.id !== id) return g;
        touched = { ...g, name };
        return touched;
      })
    );
    if (touched) saveGroup(touched);
  };

  const handleDeleteGroup = (id: string) => {
    const removing = groups.find((g) => g.id === id);
    setGroups((prev) => prev.filter((g) => g.id !== id));
    if (activeRequest && removing?.requests.some((r) => r.id === activeRequest.id)) {
      setActiveRequest(null);
    }
    deleteGroup(id);
  };

  // ---- Requests ----
  const handleAddRequest = (groupId: string) => {
    const req = newRequest();
    let touched: RequestGroup | undefined;
    setGroups((prev) =>
      prev.map((g) => {
        if (g.id !== groupId) return g;
        touched = { ...g, requests: [...g.requests, req] };
        return touched;
      })
    );
    if (touched) saveGroup(touched);
    setActiveRequest(req);
    setResponse(null);
  };

  const handleDeleteRequest = (groupId: string, requestId: string) => {
    let touched: RequestGroup | undefined;
    setGroups((prev) =>
      prev.map((g) => {
        if (g.id !== groupId) return g;
        touched = { ...g, requests: g.requests.filter((r) => r.id !== requestId) };
        return touched;
      })
    );
    if (touched) saveGroup(touched);
    if (activeRequest?.id === requestId) setActiveRequest(null);
  };

  // ---- Environments ----
  const handleSaveEnv = (env: Environment) => {
    setEnvironments((prev) => {
      const exists = prev.some((e) => e.id === env.id);
      return exists ? prev.map((e) => (e.id === env.id ? env : e)) : [...prev, env];
    });
    if (!activeEnvId) setActiveEnvId(env.id);
    saveEnvironment(env);
  };

  const handleDeleteEnv = (id: string) => {
    setEnvironments((prev) => prev.filter((e) => e.id !== id));
    if (activeEnvId === id) setActiveEnvId(null);
    deleteEnvironment(id);
  };

  const handleClearHistory = () => {
    setHistory([]);
    clearHistory();
  };

  return (
    <div className="flex flex-col h-screen">
      <Header
        envColor={activeEnv?.color ?? null}
        envName={activeEnv?.name ?? null}
        showHistory={showHistory}
        onToggleHistory={() => setShowHistory((v) => !v)}
      />

      <div className="flex flex-1 overflow-hidden">
        <Sidebar
          groups={groups}
          environments={environments}
          activeEnvId={activeEnvId}
          activeRequestId={activeRequest?.id ?? null}
          onSelectActiveEnv={setActiveEnvId}
          onSaveEnv={handleSaveEnv}
          onDeleteEnv={handleDeleteEnv}
          onAddGroup={handleAddGroup}
          onRenameGroup={handleRenameGroup}
          onDeleteGroup={handleDeleteGroup}
          onAddRequest={handleAddRequest}
          onSelectRequest={(req) => {
            setActiveRequest(req);
            setResponse(null);
          }}
          onDeleteRequest={handleDeleteRequest}
        />

        <main className="flex-1 flex flex-col overflow-hidden bg-[var(--bg)]">
          {activeRequest ? (
            <>
              <div className="flex-1 overflow-hidden border-b border-[var(--border)]">
                <RequestBuilder
                  request={activeRequest}
                  onChange={handleRequestChange}
                  onSend={handleSend}
                  isSending={isSending}
                />
              </div>
              <div className="h-[45%] min-h-48 overflow-hidden">
                <ResponseViewer response={response} isSending={isSending} />
              </div>
            </>
          ) : (
            <EmptyState hasGroups={groups.length > 0} loaded={loaded} />
          )}
        </main>

        {showHistory && (
          <HistoryPanel history={history} onReplay={handleReplay} onClear={handleClearHistory} />
        )}
      </div>
    </div>
  );
}

function Header({
  envColor,
  envName,
  showHistory,
  onToggleHistory,
}: {
  envColor: string | null;
  envName: string | null;
  showHistory: boolean;
  onToggleHistory: () => void;
}) {
  const { mode, cycle } = useTheme();
  const icon = mode === 'light' ? '☀' : mode === 'dark-grey' ? '☁' : '🌙';
  const label = mode === 'light' ? 'Light' : mode === 'dark-grey' ? 'Dark Grey' : 'Dark';

  return (
    <header
      className="flex items-center gap-3 px-4 h-12 shrink-0 border-b border-[var(--border)] bg-[var(--bg-elev)]"
      style={envColor ? { boxShadow: `inset 4px 0 0 ${envColor}` } : undefined}
    >
      <span className="font-semibold tracking-tight">local-postman</span>
      <span className="text-xs px-1.5 py-0.5 rounded bg-[var(--bg-elev-2)] text-[var(--muted-fg)]">
        {APP_VERSION}
      </span>
      {envName && (
        <span className="flex items-center gap-1.5 text-xs text-[var(--muted-fg)]">
          <span className="w-2 h-2 rounded-full" style={{ background: envColor ?? undefined }} />
          {envName}
        </span>
      )}
      <div className="ml-auto flex items-center gap-1">
        <button
          onClick={onToggleHistory}
          className={`px-2.5 py-1 text-xs rounded-md transition-colors ${
            showHistory
              ? 'text-[var(--fg)] bg-[var(--bg-elev-2)]'
              : 'text-[var(--muted-fg)] hover:bg-[var(--hover)]'
          }`}
        >
          History
        </button>
        <button
          onClick={cycle}
          className="w-8 h-8 flex items-center justify-center rounded-md hover:bg-[var(--hover)] text-base"
          title={`Theme: ${label} (click to cycle)`}
        >
          {icon}
        </button>
      </div>
    </header>
  );
}

function EmptyState({ hasGroups, loaded }: { hasGroups: boolean; loaded: boolean }) {
  if (!loaded) return null;
  return (
    <div className="flex-1 flex flex-col items-center justify-center gap-3 text-[var(--muted-fg)]">
      <span className="text-5xl opacity-40">⚡</span>
      <p className="text-sm">
        {hasGroups ? 'Select a request, or add a new one.' : 'Create a collection to get started.'}
      </p>
    </div>
  );
}
