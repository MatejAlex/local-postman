'use client';

import { useState } from 'react';
import type { ApiRequest, CollectionAuth, Environment, KeyValue, RequestGroup } from '../lib/types';
import { badgeOf, collectionAuthOf, collectionVariablesOf } from '../lib/types';
import EnvironmentManager from './EnvironmentManager';
import BasicAuthFields from './BasicAuthFields';
import ConfirmDialog from './ConfirmDialog';
import KeyValueEditor from './KeyValueEditor';
import { variableMapOf } from '../lib/utils';

export interface CollectionSettings {
  auth: CollectionAuth;
  variables: KeyValue[];
}

interface Props {
  groups: RequestGroup[];
  environments: Environment[];
  activeEnvId: string | null;
  activeRequestId: string | null;
  envVars: Record<string, string>;
  onSelectActiveEnv: (id: string | null) => void;
  onSaveEnv: (env: Environment) => void;
  onDeleteEnv: (id: string) => void;
  onAddGroup: () => void;
  onRenameGroup: (id: string, name: string) => void;
  onDeleteGroup: (id: string) => void;
  onSaveCollection: (groupId: string, settings: CollectionSettings) => void;
  onAddRequest: (groupId: string, kind?: 'http' | 'mcp') => void;
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
            envVars={props.envVars}
            onRename={(name) => props.onRenameGroup(group.id, name)}
            onDelete={() => props.onDeleteGroup(group.id)}
            onSaveSettings={(settings) => props.onSaveCollection(group.id, settings)}
            onAddRequest={(kind) => props.onAddRequest(group.id, kind)}
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
  envVars,
  onRename,
  onDelete,
  onSaveSettings,
  onAddRequest,
  onSelectRequest,
  onDeleteRequest,
}: {
  group: RequestGroup;
  activeRequestId: string | null;
  envVars: Record<string, string>;
  onRename: (name: string) => void;
  onDelete: () => void;
  onSaveSettings: (settings: CollectionSettings) => void;
  onAddRequest: (kind?: 'http' | 'mcp') => void;
  onSelectRequest: (req: ApiRequest) => void;
  onDeleteRequest: (requestId: string) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  const [renaming, setRenaming] = useState(false);
  const [editingSettings, setEditingSettings] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [name, setName] = useState(group.name);

  const auth = collectionAuthOf(group);
  const variables = collectionVariablesOf(group);
  const activeVariables = variables.filter((v) => v.enabled && v.key.trim()).length;
  const isConfigured = auth.mode === 'basic' || activeVariables > 0;

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
          onClick={() => setEditingSettings(true)}
          className={`w-5 hover:text-[var(--accent)] ${
            isConfigured
              ? 'text-[var(--accent)]'
              : 'opacity-0 group-hover:opacity-100 text-[var(--muted-fg)]'
          }`}
          title={settingsHint(auth, activeVariables)}
        >
          ⚙
        </button>
        <button
          onClick={() => onAddRequest('http')}
          className="opacity-0 group-hover:opacity-100 w-5 text-[var(--muted-fg)] hover:text-[var(--accent)]"
          title="Add request"
        >
          +
        </button>
        <button
          onClick={() => onAddRequest('mcp')}
          className="opacity-0 group-hover:opacity-100 w-5 text-[10px] font-bold text-[var(--muted-fg)] hover:text-[var(--accent)]"
          title="Add MCP request"
        >
          M
        </button>
        <button
          onClick={() => setConfirmingDelete(true)}
          className="opacity-0 group-hover:opacity-100 w-5 text-[var(--muted-fg)] hover:text-[var(--danger)]"
          title="Delete collection"
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
              <span className={`text-[10px] font-bold w-12 shrink-0 method-${badgeOf(req)}`}>
                {badgeOf(req)}
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
            <div className="flex flex-col">
              <button
                onClick={() => onAddRequest('http')}
                className="w-full text-left pl-2 py-1.5 text-xs text-[var(--muted-fg)] hover:text-[var(--accent)]"
              >
                + Add request
              </button>
              <button
                onClick={() => onAddRequest('mcp')}
                className="w-full text-left pl-2 py-1.5 text-xs text-[var(--muted-fg)] hover:text-[var(--accent)]"
              >
                + Add MCP request
              </button>
            </div>
          )}
        </div>
      )}

      {editingSettings && (
        <CollectionSettingsModal
          groupName={group.name}
          auth={auth}
          variables={variables}
          envVars={envVars}
          onClose={() => setEditingSettings(false)}
          onSave={(settings) => {
            onSaveSettings(settings);
            setEditingSettings(false);
          }}
        />
      )}

      {confirmingDelete && (
        <ConfirmDialog
          title={`Delete "${group.name}"?`}
          message={deleteWarning(group)}
          onConfirm={() => {
            setConfirmingDelete(false);
            onDelete();
          }}
          onCancel={() => setConfirmingDelete(false)}
        />
      )}
    </div>
  );
}

function settingsHint(auth: CollectionAuth, activeVariables: number): string {
  const set: string[] = [];
  if (auth.mode === 'basic') {
    set.push('Basic auth');
  }
  if (activeVariables > 0) {
    set.push(`${activeVariables} variable${activeVariables === 1 ? '' : 's'}`);
  }
  return set.length === 0 ? 'Collection settings' : `Collection settings — ${set.join(', ')}`;
}

function deleteWarning(group: RequestGroup): string {
  const count = group.requests.length;
  if (count === 0) {
    return 'This collection is empty. Deleting it cannot be undone.';
  }
  return `Its ${count} request${count === 1 ? '' : 's'} go with it, along with the collection's auth and variables. This cannot be undone.`;
}

function CollectionSettingsModal({
  groupName,
  auth,
  variables,
  envVars,
  onClose,
  onSave,
}: {
  groupName: string;
  auth: CollectionAuth;
  variables: KeyValue[];
  envVars: Record<string, string>;
  onClose: () => void;
  onSave: (settings: CollectionSettings) => void;
}) {
  const [draft, setDraft] = useState<CollectionSettings>({ auth, variables });

  // Preview against the draft, so a token typed here resolves in the auth fields straight away.
  const vars: Record<string, string> = { ...variableMapOf(draft.variables), ...envVars };
  const shadowed = draft.variables.filter(
    (v) => v.enabled && v.key.trim() && Object.prototype.hasOwnProperty.call(envVars, v.key)
  );

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg max-h-[85vh] overflow-auto rounded-lg bg-[var(--bg-elev)] border border-[var(--border)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="p-4 border-b border-[var(--border)]">
          <p className="text-sm font-medium">Collection settings</p>
          <p className="text-xs text-[var(--muted-fg)] truncate">{groupName}</p>
        </div>

        <div className="flex flex-col gap-5 p-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)] mb-2">
              Variables — reference with {'{{key}}'}
            </p>
            <KeyValueEditor
              rows={draft.variables}
              onChange={(next) => setDraft({ ...draft, variables: next })}
              keyPlaceholder="token"
              valuePlaceholder="value"
            />
            <p className="mt-2 text-xs text-[var(--muted-fg)]">
              Available to every request in {groupName}, in the URL, params, headers and body.
              The active environment wins on a name clash.
            </p>
            {shadowed.length > 0 && (
              <p className="mt-1 text-xs text-[var(--warn)]">
                Overridden by the active environment: {shadowed.map((v) => v.key).join(', ')}
              </p>
            )}
          </div>

          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)] mb-2">
              Auth
            </p>
            <div className="flex items-center gap-2 mb-3">
              {(['none', 'basic'] as const).map((mode) => (
                <button
                  key={mode}
                  onClick={() => setDraft({ ...draft, auth: { ...draft.auth, mode } })}
                  className={`px-3 py-1 text-xs rounded-md border transition-colors ${
                    draft.auth.mode === mode
                      ? 'border-[var(--accent)] text-[var(--accent)] bg-[var(--accent-soft)]'
                      : 'border-[var(--border)] text-[var(--muted-fg)] hover:text-[var(--fg)]'
                  }`}
                >
                  {mode === 'none' ? 'No auth' : 'Basic'}
                </button>
              ))}
            </div>

            {draft.auth.mode === 'basic' ? (
              <BasicAuthFields
                value={draft.auth.basic}
                onChange={(basic) => setDraft({ ...draft, auth: { ...draft.auth, basic } })}
                vars={vars}
              />
            ) : (
              <p className="text-sm text-[var(--muted-fg)]">
                Requests in this collection send no Authorization header unless they set their own.
              </p>
            )}
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 p-4 border-t border-[var(--border)]">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-sm text-[var(--muted-fg)] hover:bg-[var(--hover)] rounded-md"
          >
            Cancel
          </button>
          <button
            onClick={() => onSave(draft)}
            className="px-4 py-1.5 text-sm font-semibold rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:opacity-90"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
