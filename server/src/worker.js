export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const url = new URL(request.url);
    if (url.pathname !== '/push') {
      return json({ error: 'Not found' }, 404);
    }

    const auth = request.headers.get('Authorization');
    if (auth !== `Bearer ${env.API_KEY}`) {
      return json({ error: 'Unauthorized' }, 401);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'Invalid JSON' }, 400);
    }

    const { token, event, attributes, contentState } = body;
    if (!token || !event) {
      return json({ error: 'Missing token or event' }, 400);
    }

    try {
      const jwt = await createJWT(env.TEAM_ID, env.KEY_ID, env.P8_KEY);

      const payload = { aps: buildAPS(event, attributes, contentState) };

      const apnsHost = env.USE_SANDBOX === 'true'
        ? 'https://api.sandbox.push.apple.com'
        : 'https://api.push.apple.com';

      const res = await fetch(`${apnsHost}/3/device/${token}`, {
        method: 'POST',
        headers: {
          'authorization': `bearer ${jwt}`,
          'apns-topic': `${env.BUNDLE_ID}.push-type.liveactivity`,
          'apns-push-type': 'liveactivity',
          'apns-priority': '10',
        },
        body: JSON.stringify(payload),
      });

      const resBody = await res.text();

      if (res.status === 200) {
        return json({ success: true });
      } else {
        return json({ success: false, status: res.status, error: resBody }, 502);
      }
    } catch (err) {
      return json({ success: false, error: err.message }, 500);
    }
  }
};

function buildAPS(event, attributes, contentState) {
  const aps = {
    timestamp: Math.floor(Date.now() / 1000),
    event,
    'content-state': contentState || { isRunning: event === 'start' },
  };

  if (event === 'start' && attributes) {
    aps['attributes-type'] = 'TimerActivityAttributes';
    aps.attributes = attributes;
    aps.alert = {
      title: 'Timer Started',
      body: `Tracking ${attributes.issueKey || 'task'}`,
    };
  }

  if (event === 'end') {
    aps['dismissal-date'] = Math.floor(Date.now() / 1000);
  }

  return aps;
}

async function createJWT(teamId, keyId, p8Key) {
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;

  const pem = p8Key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const keyData = Uint8Array.from(atob(pem), c => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );

  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );

  return `${signingInput}.${base64url(sig)}`;
}

function base64url(input) {
  if (typeof input === 'string') {
    return btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  }
  const bytes = new Uint8Array(input instanceof ArrayBuffer ? input : input.buffer);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}
