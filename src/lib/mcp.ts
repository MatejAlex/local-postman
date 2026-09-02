// The MCP side of the app: which methods can be sent, and what each one needs.
//
// MCP over Streamable HTTP is plain JSON-RPC over POST, so an MCP request is an
// ordinary HTTP request with a fixed shape. That is why it reuses the URL, the
// headers, the auth panel and the {{variable}} substitution rather than getting
// a parallel set of its own.

/** The protocol revision we advertise on `initialize`. */
export const MCP_PROTOCOL_VERSION = '2025-06-18';

export type McpMethod =
  | 'tools/list'
  | 'tools/call'
  | 'prompts/list'
  | 'prompts/get'
  | 'resources/list'
  | 'resources/read'
  | 'ping';

export const MCP_METHODS: McpMethod[] = [
  'tools/list',
  'tools/call',
  'prompts/list',
  'prompts/get',
  'resources/list',
  'resources/read',
  'ping',
];

/**
 * Which methods need a target named, and what that target is called.
 * `tools/call` names a tool, `prompts/get` a prompt, `resources/read` a URI.
 * The list methods need nothing, which is what makes them the safe first click.
 */
export const MCP_TARGET_LABEL: Partial<Record<McpMethod, string>> = {
  'tools/call': 'Tool name',
  'prompts/get': 'Prompt name',
  'resources/read': 'Resource URI',
};

/** Methods that take a free-form JSON argument object. */
export const MCP_TAKES_ARGUMENTS: McpMethod[] = ['tools/call', 'prompts/get'];

export interface McpConfig {
  method: McpMethod;
  /** Tool name, prompt name or resource URI, depending on `method`. */
  target: string;
  /** JSON object of arguments, as typed. Empty means "no arguments". */
  args: string;
}

export function emptyMcpConfig(): McpConfig {
  return { method: 'tools/list', target: '', args: '' };
}

export function mcpNeedsTarget(method: McpMethod): boolean {
  return method in MCP_TARGET_LABEL;
}

export function mcpTakesArguments(method: McpMethod): boolean {
  return MCP_TAKES_ARGUMENTS.includes(method);
}

/**
 * Turn a config into JSON-RPC `params`, or explain why it cannot be.
 *
 * Bad JSON in the arguments box is caught here rather than at the server, so
 * the message names the box the user is looking at instead of arriving as a
 * protocol error from three hops away.
 */
export function mcpParamsFor(config: McpConfig): { params: Record<string, unknown> } | { error: string } {
  const { method, target } = config;

  if (mcpNeedsTarget(method) && target.trim() === '') {
    return { error: `${MCP_TARGET_LABEL[method]} is required for ${method}.` };
  }

  let args: Record<string, unknown> = {};
  if (mcpTakesArguments(method) && config.args.trim() !== '') {
    try {
      const parsed = JSON.parse(config.args);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return { error: 'Arguments must be a JSON object, e.g. {"query": "payrun"}.' };
      }
      args = parsed as Record<string, unknown>;
    } catch (err) {
      return { error: `Arguments are not valid JSON: ${err instanceof Error ? err.message : 'parse error'}` };
    }
  }

  switch (method) {
    case 'tools/call':
      return { params: { name: target.trim(), arguments: args } };
    case 'prompts/get':
      return { params: { name: target.trim(), arguments: args } };
    case 'resources/read':
      return { params: { uri: target.trim() } };
    default:
      return { params: {} };
  }
}
