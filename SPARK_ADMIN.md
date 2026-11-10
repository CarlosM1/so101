# Spark administration

For whoever administers the Academy's DGX Spark. Students don't need any of this: they never log in to
the Spark, they only run the robot client on their PC ([README](README.md) §10).

The Spark runs one thing for the Academy: the LeRobot **policy server** (Docker, `compose.spark.yml`),
on port **8090**. Each student's robot client tells it which policy to load.

## 1. A dedicated `academy` user (one time, as an admin)
The Spark is shared, so the project lives under its own user. Nobody logs in as `academy`: you switch to
it from your admin account.
```bash
ssh <admin>@<SPARK_HOST>
sudo adduser academy                    # lowercase: Ubuntu rejects capitals. Optional fields: just Enter
sudo usermod -aG docker academy         # lets it run Docker (note: the docker group is root-equivalent)
echo "DenyUsers academy" | sudo tee /etc/ssh/sshd_config.d/deny-academy.conf
sudo systemctl reload ssh               # no SSH logins as academy
sudo passwd -l academy                  # no password logins at all
sudo -iu academy                        # become academy (asks for YOUR password)
```

## 2. Get the project onto the Spark and build
As `academy`, either clone the repository (needs read access to it from the Spark), or copy it from your
PC through your admin account (`academy` can't receive SSH):
```bash
# option A, on the Spark as academy
git clone <repository URL> ~/SO101

# option B, from the PC folder, then move it on the Spark
rsync -av --exclude data --exclude .venv --exclude outputs --exclude snapshots --exclude 'logs' \
  ./ <admin>@<SPARK_HOST>:~/SO101/
#   on the Spark, as <admin>:
sudo cp -r ~/SO101 /home/academy/ && sudo chown -R academy:academy /home/academy/SO101 && rm -rf ~/SO101
```
Then, as `academy`:
```bash
cd ~/SO101
cp .env.example .env                    # set HF_USER / HF_TOKEN (a read token is enough here)
docker compose -f compose.spark.yml build                               # ~7 GB image, once
docker compose -f compose.spark.yml --profile tools run --rm shell scripts/00_check.sh
# expect: CUDA: NVIDIA GB10 … and "GPU matmul ok"
```
The `.env` on the Spark only matters for `POLICY_SERVER_PORT` (keep it **8090**) and the HF token: the
policy itself is chosen by each robot client (README §10). DGX OS ships with Docker and the NVIDIA Container
Toolkit.

**Always run the Spark commands as `academy`, from `/home/academy/SO101`.** Docker Compose names the
project after the folder (`so101`), so running `docker compose … up` from another user's copy of the
folder would replace academy's policy server with one using *that* copy's files and `.env`.

## 3. Start the policy server

As `academy` in `~/SO101`, start the server. It stays up and restarts by itself after a crash or a reboot:
```bash
docker compose -f compose.spark.yml up -d policy-server     # start in the background
docker compose -f compose.spark.yml logs -f policy-server   # watch it; Ctrl+C stops watching, not the server
```
Healthy: the log shows `--port=8090` and then waits quietly for a client. The server loads **no policy**
by itself.

To update after a `git pull` (as `academy`, in `~/SO101`):
```bash
docker compose -f compose.spark.yml build
docker compose -f compose.spark.yml up -d policy-server
```

## 4. Troubleshooting

| Problem | Cause / fix |
|---|---|
| Policy server keeps `Restarting`, log says `Address already in use` | another program uses the port. Find it with `sudo ss -ltnp \| grep :<port>` (on a shared machine, 8080 is often taken). Change `POLICY_SERVER_PORT` in the **Spark's** `/home/academy/SO101/.env`, then `docker compose -f compose.spark.yml restart policy-server`, and use the same port on every PC |
| `adduser: Please enter a username matching …` | Linux usernames must be lowercase: `academy`, not `ACADEMY` |
| `sudo: a terminal is required to read the password` during `rsync --rsync-path="sudo …"` | copy to your own home first, then `sudo cp` as in §2 |
