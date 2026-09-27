#!/usr/bin/env bash
#
# Sets up throwaway remotes that make Git and SSH ask for credentials, for trying the app's
# password, passphrase and host key sheets by hand. Everyday use is an SSH key already in the
# agent, which never asks, so each prompting path needs a remote set up on purpose. The steps for
# each scenario are in Scripts/README.md.
#
#   Scripts/credential-scenarios.sh start <folder>
#   Scripts/credential-scenarios.sh change-host-key <folder>
#   Scripts/credential-scenarios.sh stop <folder>
#
# Everything stays in <folder> and on 127.0.0.1: an SSH server on port 2222 that lets in only this
# folder's key, run as you with its own host key, and an HTTP server on port 8765 that takes the
# username "git" with the token "good-token". Nothing is added to ~/.ssh, the SSH agent or the
# Keychain, except by the Keychain scenario, which says how to remove what it adds.

set -euo pipefail

readonly SSH_PORT=2222
readonly HTTP_PORT=8765
readonly TOKEN="good-token"
readonly PASSPHRASE="secret"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || fail "usage: $0 start|change-host-key|stop <folder>"
readonly ACTION="$1"
mkdir -p "$2"
readonly ROOT="$(cd "$2" && pwd -P)"
readonly SERVER="$ROOT/server"

# The test repositories' commits, whoever runs this.
export GIT_AUTHOR_NAME="Credential Scenarios" GIT_AUTHOR_EMAIL="scenarios@example.com"
export GIT_COMMITTER_NAME="Credential Scenarios" GIT_COMMITTER_EMAIL="scenarios@example.com"

start_ssh_server() {
    cat > "$SERVER/sshd_config" <<EOF
Port $SSH_PORT
ListenAddress 127.0.0.1
HostKey $SERVER/host_key
AuthorizedKeysFile $SERVER/authorized_keys
PidFile $SERVER/sshd.pid
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
EOF
    /usr/sbin/sshd -f "$SERVER/sshd_config" -E "$SERVER/sshd.log"
}

stop_servers() {
    for pid_file in "$SERVER/sshd.pid" "$SERVER/http.pid" "$SERVER/agent.pid"; do
        if [[ -f "$pid_file" ]]; then
            kill "$(cat "$pid_file")" 2>/dev/null || true
            rm -f "$pid_file"
        fi
    done
}

# Git's own HTTP server program behind a small Python server that asks for the token first.
write_http_server() {
    cat > "$SERVER/http_server.py" <<'EOF'
import base64, os, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, ROOT, TOKEN = int(sys.argv[1]), sys.argv[2], sys.argv[3]
BACKEND = subprocess.check_output(["git", "--exec-path"], text=True).strip() + "/git-http-backend"
EXPECTED = "Basic " + base64.b64encode(f"git:{TOKEN}".encode()).decode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self): self.serve()
    def do_POST(self): self.serve()

    def serve(self):
        if self.headers.get("Authorization") != EXPECTED:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="credential scenarios"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        path, _, query = self.path.partition("?")
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        environment = dict(os.environ, GIT_PROJECT_ROOT=ROOT, GIT_HTTP_EXPORT_ALL="1", PATH_INFO=path,
                           QUERY_STRING=query, REQUEST_METHOD=self.command, REMOTE_USER="git",
                           CONTENT_TYPE=self.headers.get("Content-Type", ""), CONTENT_LENGTH=str(len(body)),
                           GIT_PROTOCOL=self.headers.get("Git-Protocol", ""))
        output = subprocess.run([BACKEND], input=body, env=environment, capture_output=True).stdout
        head, _, rest = output.partition(b"\r\n\r\n")
        status, headers = 200, []
        for line in head.decode().split("\r\n"):
            name, _, value = line.partition(": ")
            if name.lower() == "status":
                status = int(value.split()[0])
            elif name:
                headers.append((name, value))
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(rest)))
        self.end_headers()
        self.wfile.write(rest)

    def log_message(self, *arguments):
        pass

ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
EOF
}

ssh_command() {
    local known_hosts="$1" agent="$2"
    echo "ssh -F /dev/null -p $SSH_PORT -o UserKnownHostsFile=$known_hosts -o IdentitiesOnly=yes -i $SERVER/client_key -o IdentityAgent=$agent"
}

start() {
    [[ ! -e "$SERVER" ]] || fail "$ROOT is already set up. Stop it and remove the folder to start again."
    mkdir -p "$SERVER"
    ssh-keygen -q -t ed25519 -N "" -C "credential scenarios host" -f "$SERVER/host_key"
    ssh-keygen -q -t ed25519 -N "$PASSPHRASE" -C "credential scenarios client" -f "$SERVER/client_key"
    cp "$SERVER/client_key.pub" "$SERVER/authorized_keys"
    chmod 600 "$SERVER/authorized_keys"

    git init --quiet --bare --initial-branch=main "$SERVER/remote.git"
    git -C "$SERVER/remote.git" config http.receivepack true
    git init --quiet --initial-branch=main "$SERVER/seed"
    echo "Credential scenarios" > "$SERVER/seed/README.md"
    git -C "$SERVER/seed" add README.md
    git -C "$SERVER/seed" commit --quiet --message "First commit"
    git -C "$SERVER/seed" push --quiet "$SERVER/remote.git" main

    start_ssh_server
    write_http_server
    python3 "$SERVER/http_server.py" "$HTTP_PORT" "$SERVER" "$TOKEN" > "$SERVER/http.log" 2>&1 &
    echo $! > "$SERVER/http.pid"

    # An agent of its own holding the key, for the everyday case. Its socket's path has to fit in
    # 104 bytes, which a folder deep in the file system can't promise. SSH_ASKPASS gives ssh-add
    # the passphrase without a prompt.
    local agent_socket
    agent_socket="$(mktemp -d /tmp/credential-scenarios.XXXXXX)/agent.sock"
    echo "$agent_socket" > "$SERVER/agent.path"
    eval "$(ssh-agent -s -a "$agent_socket")" > /dev/null
    echo "$SSH_AGENT_PID" > "$SERVER/agent.pid"
    printf '#!/bin/sh\necho %s\n' "$PASSPHRASE" > "$SERVER/passphrase.sh"
    chmod +x "$SERVER/passphrase.sh"
    SSH_ASKPASS="$SERVER/passphrase.sh" SSH_ASKPASS_REQUIRE=force ssh-add -q "$SERVER/client_key" < /dev/null
    rm "$SERVER/passphrase.sh"

    # Each clone keeps its SSH settings and known hosts to itself, so the scenarios leave ~/.ssh alone.
    local ssh_url="ssh://$USER@127.0.0.1:$SSH_PORT$SERVER/remote.git"
    local http_url="http://127.0.0.1:$HTTP_PORT/remote.git"
    for clone in ssh-agent ssh-passphrase; do
        git clone --quiet "$SERVER/remote.git" "$ROOT/$clone"
        git -C "$ROOT/$clone" remote set-url origin "$ssh_url"
        : > "$SERVER/$clone-known_hosts"
    done
    git -C "$ROOT/ssh-agent" config core.sshCommand "$(ssh_command "$SERVER/ssh-agent-known_hosts" "$agent_socket")"
    git -C "$ROOT/ssh-passphrase" config core.sshCommand "$(ssh_command "$SERVER/ssh-passphrase-known_hosts" none)"
    for clone in https-token https-keychain; do
        git clone --quiet "$SERVER/remote.git" "$ROOT/$clone"
        git -C "$ROOT/$clone" remote set-url origin "$http_url"
    done
    # An empty helper turns off any helper the system or global configuration sets, so this clone
    # asks every time. The Keychain clone keeps whatever the configuration sets, as Terminal does.
    git -C "$ROOT/https-token" config credential.helper ""

    echo "Ready in $ROOT:"
    echo "  ssh-agent        SSH, key in an agent of its own, known hosts empty"
    echo "  ssh-passphrase   SSH, key not in any agent (passphrase: $PASSPHRASE), known hosts empty"
    echo "  https-token      HTTP, username git, token $TOKEN, nothing remembered"
    echo "  https-keychain   HTTP, remembered by your configured credential helper"
    echo "To push a commit from elsewhere: git -C $SERVER/seed commit --allow-empty -m Elsewhere && git -C $SERVER/seed push $SERVER/remote.git main"
}

change_host_key() {
    [[ -f "$SERVER/sshd.pid" ]] || fail "$ROOT isn't running."
    kill "$(cat "$SERVER/sshd.pid")"
    rm -f "$SERVER/sshd.pid" "$SERVER/host_key" "$SERVER/host_key.pub"
    ssh-keygen -q -t ed25519 -N "" -C "credential scenarios host" -f "$SERVER/host_key"
    # Give the old server a moment to let go of the port.
    sleep 1
    start_ssh_server
    echo "The SSH server now has a different host key from the one the clones remember."
}

case "$ACTION" in
    start) start ;;
    change-host-key) change_host_key ;;
    stop)
        stop_servers
        if [[ -f "$SERVER/agent.path" ]]; then
            rm -rf "$(dirname "$(cat "$SERVER/agent.path")")"
            rm "$SERVER/agent.path"
        fi
        echo "Stopped. Remove $ROOT when done."
        ;;
    *) fail "usage: $0 start|change-host-key|stop <folder>" ;;
esac
