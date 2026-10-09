cask "skillspack" do
  version "0.1.0"
  # Scripts/release.sh rewrites version and sha256 on every release. Until the first release
  # the checksum is a placeholder and the download URL does not resolve.
  sha256 "361a2a71d76addd490483482cfbb891560e506755bc145dd56ab8c130f903a68"

  url "https://github.com/InsaneArts/SkillsPack/releases/download/v#{version}/SkillsPack.dmg"
  name "SkillsPack"
  desc "Menu bar manager for Claude Code, Codex and pi agent skills"
  homepage "https://github.com/InsaneArts/SkillsPack"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "SkillsPack.app"

  uninstall quit: "dev.tgomareli.skillspack"

  zap trash: [
    "~/Library/Application Support/SkillsPack",
    "~/Library/Preferences/dev.tgomareli.skillspack.plist",
    "~/Library/Caches/dev.tgomareli.skillspack",
  ]

  caveats do
    <<~EOS
      SkillsPack lives in the menu bar. It reads ~/.claude, ~/.codex, ~/.agents
      and ~/.pi, and turns skills on or off through each agent's own settings.
    EOS
  end
end
