'use client';

import { useState } from 'react';
import type { ApiRequest, Environment, RequestGroup } from '../lib/types';
import EnvironmentManager from './EnvironmentManager';

interface Props {
  groups: RequestGroup[];
  environments: Environment[];
  activeEnvId: string | null;
  activeRequestId: string | null;
  onSelectActiveEnv: (id: string | null) => void;
  onSaveEnv: (env: Environment) => void;
  onDeleteEnv: (id: string) => void;
  onAddGroup: () => void;
  onRenameGroup: (id: string, name: string) => void;
  onDeleteGroup: (id: string) => void;
  onAddRequest: (groupId: string) => void;
  onSelectRequest: (req: ApiRequest) => void;
  onDeleteRequest: (groupId: string, requestId: string) => void;
}

export default function Sidebar(props: Props) {
  return (
    <aside className="w-72 shrink-0 flex flex-col bg-[var(--bg-elev)] border-r border-[var(--border)] overflow-hidden">
      <div className="p-3 border-b border-[var(--border)]">
        <EnvironmentManager
          environments={props.environments}
          activeId={props.activeEnvId}
          onSelectActive={props.onSelectActiveEnv}
          onSave={props.onSaveEnv}
          onDelete={props.onDeleteEnv}
        />
      </div>

      <div className="flex items-center justify-between px-3 pt-3 pb-1">
        <span className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)]">
          Collections
        </span>
        <button
          onClick={props.onAddGroup}
          className="text-xs text-[var(--accent)] hover:opacity-80"
          title="New group"
        >
          + Group
        </button>
      </div>

      <div className="flex-1 overflow-auto px-2 pb-3">
        {props.groups.length === 0 && (
          <p className="px-2 py-3 text-xs text-[var(--muted-fg)]">
            No collections yet. Create a group to get started.
          </p>
        )}
        {props.groups.map((group) => (
          <GroupNode
            key={group.id}
            group={group}
            activeRequestId={props.activeRequestId}
            onRename={(name) => props.onRenameGroup(group.id, name)}
            onDelete={() => props.onDeleteGroup(group.id)}
            onAddRequest={() => props.onAddRequest(group.id)}
            onSelectRequest={props.onSelectRequest}
            onDeleteRequest={(rid) => props.onDeleteRequest(group.id, rid)}
          />
        ))}
      </div>
    </aside>
  );
}

function GroupNode({
  group,
  activeRequestId,
  onRename,
  onDelete,
  onAddRequest,
  onSelectRequest,
  onDeleteRequest,
}: {
  group: RequestGroup;
  activeRequestId: string | null;
  onRename: (name: string) => void;
  onDelete: () => void;
  onAddRequest: () => void;
  onSelectRequest: (req: ApiRequest) => void;
  onDeleteRequest: (requestId: string) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  const [renaming, setRenaming] = useState(false);
  const [name, setName] = useState(group.name);

  const commitRename = () => {
    const trimmed = name.trim() || group.name;
    setName(trimmed);
    onRename(trimmed);
    setRenaming(false);
  };

  return (
    <div className="mb-1">
      <div className="group flex items-center gap-1 px-1.5 py-1.5 rounded-md hover:bg-[var(--hover)]">
        <button
          onClick={() => setExpanded((v) => !v)}
          className="w-4 text-xs text-[var(--muted-fg)]"
          aria-label={expanded ? 'Collapse' : 'Expand'}
        >
          {expanded ? '▾' : '▸'}
        </button>
        {renaming ? (
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            onBlur={commitRename}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commitRename();
              if (e.key === 'Escape') {
                setName(group.name);
                setRenaming(false);
              }
            }}
            className="flex-1 px-1 py-0.5 text-sm rounded bg-[var(--bg-elev-2)] border border-[var(--accent)] outline-none"
          />
        ) : (
          <span
            onDoubleClick={() => setRenaming(true)}
            className="flex-1 text-sm font-medium truncate cursor-default"
            title="Double-click to rename"
          >
            {group.name}
          </span>
        )}
        <span className="text-xs text-[var(--muted-fg)]">{group.requests.length}</span>
        <button
          onClick={onAddRequest}
          className="opacity-0 group-hover:opacity-100 w-5 text-[var(--muted-fg)] hover:text-[var(--accent)]"
          title="Add request"
        >
          +
        </button>
        <button
          onClick={onDelete}
          className="opacity-0 group-hover:opacity-100 w-5 text-[var(--muted-fg)] hover:text-[var(--danger)]"
          title="Delete group"
        >
          ✕
        </button>
      </div>

      {expanded && (
        <div className="ml-4 border-l border-[var(--border)]">
          {group.requests.map((req) => (
            <div
              key={req.id}
              onClick={() => onSelectRequest(req)}
              className={`group flex items-center gap-2 pl-2 pr-1 py-1.5 rounded-md cursor-pointer ${
                activeRequestId === req.id ? 'bg-[var(--accent-soft)]' : 'hover:bg-[var(--hover)]'
              }`}
            >
              <span className={`text-[10px] font-bold w-12 shrink-0 method-${req.method}`}>
                {req.method}
              </span>
              <span className="flex-1 text-sm truncate text-[var(--fg)]">{req.name}</span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDeleteRequest(req.id);
                }}
                className="opacity-0 group-hover:opacity-100 w-5 text-[var(--muted-fg)] hover:text-[var(--danger)]"
                title="Delete request"
              >
                ✕
              </button>
            </div>
          ))}
          {group.requests.length === 0 && (
            <button
              onClick={onAddRequest}
              className="w-full text-left pl-2 py-1.5 text-xs text-[var(--muted-fg)] hover:text-[var(--accent)]"
            >
              + Add request
            </button>
          )}
        </div>
      )}
    </div>
  );
}
