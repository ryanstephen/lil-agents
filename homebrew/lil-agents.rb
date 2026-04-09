cask "lil-agents" do
  version "1.2.2"
  sha256 "a4cf7d9955ffb3881c6050505a9aedd91dd553952dc3e53aa00e4eb52485ea95"

  url "https://github.com/ryanstephen/lil-agents/releases/download/v#{version}/LilAgents-v#{version}.zip",
      verified: "github.com/ryanstephen/lil-agents/"
  name "lil agents"
  desc "Tiny AI companions that live on your macOS dock"
  homepage "https://lilagents.xyz"

  depends_on macos: ">= :sonoma"

  app "lil agents.app"

  zap trash: [
    "~/Library/Preferences/xyz.lilagents.LilAgents.plist",
    "~/Library/Caches/xyz.lilagents.LilAgents",
  ]
end
