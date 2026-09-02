'use client';

import { useEffect, useRef, useState } from 'react';
import type {
  ApiRequest,
  ApiResponse,
  HistoryItem,
  RequestGroup,
  ResolvedRequest,
} from '../src/lib/types';
import {
  APP_VERSION,
  collectionAuthOf,
  moved,
  newGroup,
  newMcpRequest,
  newRequest,
  requestKindOf,
  sortGroups,
} from '../src/lib/types';
import { requestVariables, resolveMcpRequest, resolveRequest } from '../src/lib/utils';
import {
  appendHistory,
  clearHistory,
  deleteGroup,
  loadAll,
  saveGroup,
  sendResolved,
} from '../src/lib/storage';
import { useTheme } from '../src/lib/theme';
import Sidebar from '../src/components/Sidebar';
import type { CollectionSettings } from '../src/components/Sidebar';
import RequestBuilder from '../src/components/RequestBuilder';
import ResponseViewer from '../src/components/ResponseViewer';
import HistoryPanel from '../src/components/HistoryPanel';
import HistoryDetail from '../src/components/HistoryDetail';

export default function Home() {
  const [groups, setGroups] = useState<RequestGroup[]>([]);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [activeRequest, setActiveRequest] = useState<ApiRequest | null>(null);
  const [response, setResponse] = useState<ApiResponse | null>(null);
  const [isSending, setIsSending] = useState(false);
  const [showHistory, setShowHistory] = useState(true);
  const [inspectedItem, setInspectedItem] = useState<HistoryItem | null>(null);
  const [loaded, setLoaded] = useState(false);

  const saveTimers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  useEffect(() => {
    loadAll().then((snap) => {
      // Collections arrive in readdir order, which is not the order they were
      // made in and not stable between machines. Sort on the way in.
      setGroups(sortGroups(snap.groups));
      setHistory(snap.history);
      setLoaded(true);
    });
  }, []);

  const activeGroup = activeRequest
    ? (groups.find((g) => g.requests.some((r) => r.id === activeRequest.id)) ?? null)
    : null;
  const activeCollectionAuth = activeGroup ? collectionAuthOf(activeGroup) : null;
  const vars = requestVariables(activeGroup);

  // Persist a group, debounced per-group so rapid edits collapse into one write.
  const queueSaveGroup = (group: RequestGroup) => {
    clearTimeout(saveTimers.current[group.id]);
    saveTimers.current[group.id] = setTimeout(() => saveGroup(group), 400);
  };

  /** Swap one group in place, and hand the new value back so the caller can persist it. */
  const replaceGroup = (touched: RequestGroup) => {
    setGroups(groups.map((g) => (g.id === touched.id ? touched : g)));
  };

  // ---- Request editing ----
  const handleRequestChange = (updated: ApiRequest) => {
    setActiveRequest(updated);
    const owner = groups.find((g) => g.requests.some((r) => r.id === updated.id));
    if (!owner) {
      return;
    }
    const touched = {
      ...owner,
      requests: owner.requests.map((r) => (r.id === updated.id ? updated : r)),
    };
    replaceGroup(touched);
    queueSaveGroup(touched);
  };

  // ---- Send ----
  const handleSend = async () => {
    if (!activeRequest) return;

    let resolved: ResolvedRequest;
    if (requestKindOf(activeRequest) === 'mcp') {
      const built = resolveMcpRequest(activeRequest, activeGroup);
      if ('error' in built) {
        // A malformed arguments box is the user's typo, not a failed request, so
        // it never reaches the network and never lands in history.
        setResponse({
          status: 0,
          statusText: '',
          headers: {},
          body: '',
          contentType: '',
          timeMs: 0,
          sizeBytes: 0,
          error: built.error,
        });
        return;
      }
      resolved = built.resolved;
    } else {
      resolved = resolveRequest(activeRequest, activeGroup);
    }

    setIsSending(true);
    setResponse(null);
    const resp = await sendResolved(resolved);
    setResponse(resp);
    setIsSending(false);

    const item: HistoryItem = {
      id: `h-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      timestamp: Date.now(),
      name: activeRequest.name,
      method: activeRequest.method,
      url: resolved.url,
      resolved,
      response: resp,
    };
    setHistory((prev) => [item, ...prev].slice(0, 50));
    appendHistory(item, history);
  };

  const handleReplay = async (item: HistoryItem) => {
    setInspectedItem(null);
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
    const target = groups.find((g) => g.id === id);
    if (!target) {
      return;
    }
    const touched = { ...target, name };
    replaceGroup(touched);
    saveGroup(touched);
  };

  const handleSaveCollection = (id: string, settings: CollectionSettings) => {
    const target = groups.find((g) => g.id === id);
    if (!target) {
      return;
    }
    const touched = {
      ...target,
      auth: settings.auth,
      variables: settings.variables,
      color: settings.color,
    };
    replaceGroup(touched);
    saveGroup(touched);
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
  const handleAddRequest = (groupId: string, kind: 'http' | 'mcp' = 'http') => {
    const target = groups.find((g) => g.id === groupId);
    if (!target) {
      return;
    }
    const req = kind === 'mcp' ? newMcpRequest() : newRequest();
    const touched = { ...target, requests: [...target.requests, req] };
    replaceGroup(touched);
    saveGroup(touched);
    setActiveRequest(req);
    setResponse(null);
  };

  const handleDeleteRequest = (groupId: string, requestId: string) => {
    const target = groups.find((g) => g.id === groupId);
    if (!target) {
      return;
    }
    const touched = { ...target, requests: target.requests.filter((r) => r.id !== requestId) };
    replaceGroup(touched);
    saveGroup(touched);
    if (activeRequest?.id === requestId) {
      setActiveRequest(null);
    }
  };

  // ---- Reordering ----
  /**
   * Persist the new sidebar order. Every collection is rewritten because `order`
   * is a position in one list: moving one row shifts everything after it, and a
   * half-written list would sort into an order nobody asked for.
   */
  const handleReorderGroups = (from: number, to: number) => {
    const next = moved(groups, from, to).map((g, i) => ({ ...g, order: i }));
    setGroups(next);
    next.forEach(saveGroup);
  };

  /** Requests are an array inside one file, so their order is just that array. */
  const handleReorderRequests = (groupId: string, from: number, to: number) => {
    const target = groups.find((g) => g.id === groupId);
    if (!target) {
      return;
    }
    const touched = { ...target, requests: moved(target.requests, from, to) };
    replaceGroup(touched);
    saveGroup(touched);
  };

  const handleClearHistory = () => {
    setHistory([]);
    clearHistory();
  };

  return (
    <div className="flex flex-col h-screen">
      <Header
        color={activeGroup?.color ?? null}
        collectionName={activeGroup?.name ?? null}
        showHistory={showHistory}
        onToggleHistory={() => setShowHistory((v) => !v)}
      />

      <div className="flex flex-1 overflow-hidden">
        <Sidebar
          groups={groups}
          activeRequestId={activeRequest?.id ?? null}
          onAddGroup={handleAddGroup}
          onRenameGroup={handleRenameGroup}
          onDeleteGroup={handleDeleteGroup}
          onSaveCollection={handleSaveCollection}
          onAddRequest={handleAddRequest}
          onSelectRequest={(req) => {
            setActiveRequest(req);
            setResponse(null);
          }}
          onDeleteRequest={handleDeleteRequest}
          onReorderGroups={handleReorderGroups}
          onReorderRequests={handleReorderRequests}
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
                  collectionAuth={activeCollectionAuth}
                  vars={vars}
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
          <HistoryPanel
            history={history}
            onInspect={setInspectedItem}
            onReplay={handleReplay}
            onClear={handleClearHistory}
          />
        )}
      </div>

      {inspectedItem && (
        <HistoryDetail
          item={inspectedItem}
          onReplay={handleReplay}
          onClose={() => setInspectedItem(null)}
        />
      )}
    </div>
  );
}

function Header({
  color,
  collectionName,
  showHistory,
  onToggleHistory,
}: {
  color: string | null;
  collectionName: string | null;
  showHistory: boolean;
  onToggleHistory: () => void;
}) {
  const { mode, cycle } = useTheme();
  const icon = mode === 'light' ? '☀' : mode === 'dark-grey' ? '☁' : '🌙';
  const label = mode === 'light' ? 'Light' : mode === 'dark-grey' ? 'Dark Grey' : 'Dark';

  return (
    <header
      className="flex items-center gap-3 px-4 h-12 shrink-0 border-b border-[var(--border)] bg-[var(--bg-elev)]"
      style={color ? { boxShadow: `inset 4px 0 0 ${color}` } : undefined}
    >
      <span className="font-semibold tracking-tight">local-postman</span>
      <span className="text-xs px-1.5 py-0.5 rounded bg-[var(--bg-elev-2)] text-[var(--muted-fg)]">
        {APP_VERSION}
      </span>
      {collectionName && (
        <span className="flex items-center gap-1.5 text-xs text-[var(--muted-fg)]">
          <span className="w-2 h-2 rounded-full" style={{ background: color ?? undefined }} />
          {collectionName}
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
