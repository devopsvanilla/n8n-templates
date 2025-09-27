-- Schema for mapping Intercom conversations to Teams messages
CREATE TABLE IF NOT EXISTS conversation_threads (
  intercom_conversation_id TEXT PRIMARY KEY,
  team_id TEXT NOT NULL,
  channel_id TEXT NOT NULL,
  teams_message_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Keep updated_at in sync
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_conversation_threads ON conversation_threads;
CREATE TRIGGER trg_update_conversation_threads
BEFORE UPDATE ON conversation_threads
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
