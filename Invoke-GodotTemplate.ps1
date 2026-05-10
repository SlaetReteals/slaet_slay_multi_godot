<#
.SYNOPSIS
    The Ultimate Godot 4 Scaffold Script (v1.4.0).
.DESCRIPTION
    Creates a domain-driven architecture for a LAN Multiplayer VS/TD game.
    Injects UIDs, BOM-free UTF-8 files, SVG assets, networking logic, and
    automatically downloads AssetLib plugins from GitHub.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$BasePath = (Get-Location).Path
)

# --- Configuration ---
$TemplateVersion = "1.4.0"

$PluginsToInstall = @(
    [PSCustomObject]@{
        Name = "godot_state_charts"
        Url  = "https://github.com/derkork/godot-statecharts/archive/refs/heads/main.zip"
    },
    [PSCustomObject]@{
        Name = "phantom_camera"
        Url  = "https://github.com/ramokz/phantom-camera/archive/refs/heads/main.zip"
    }
)

# --- Godot 4 Template Generators ---
function Get-GodotUid {
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $uid = -join ((1..13) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return "uid://$uid"
}

function Get-SceneContent {
    param([string]$NodeName, [string]$NodeType = "Node2D")
    $uid = Get-GodotUid
    $uniqueId = Get-Random -Minimum 1000000000 -Maximum 4294967295
    return "[gd_scene format=3 uid=`"$uid`"]`n`n[node name=`"$NodeName`" type=`"$NodeType`" unique_id=$uniqueId]`nmetadata/TemplateVersion = `"$TemplateVersion`"`n"
}

# --- Asset Templates (SVGs) ---

$SvgPlayer = @"
<svg width="64" height="64" xmlns="http://www.w3.org/2000/svg">
  <circle cx="32" cy="32" r="32" fill="#3B82F6"/>
  <rect x="32" y="24" width="24" height="16" rx="4" fill="#93C5FD"/>
</svg>
"@

$SvgEnemy = @"
<svg width="64" height="64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#EF4444"/>
  <circle cx="20" cy="24" r="8" fill="#7F1D1D"/>
  <circle cx="44" cy="24" r="8" fill="#7F1D1D"/>
</svg>
"@

$SvgTower = @"
<svg width="64" height="64" xmlns="http://www.w3.org/2000/svg">
  <rect x="8" y="8" width="48" height="48" rx="8" fill="#64748B"/>
  <circle cx="32" cy="32" r="16" fill="#1E293B"/>
</svg>
"@

$SvgGem = @"
<svg width="24" height="24" xmlns="http://www.w3.org/2000/svg">
  <polygon points="12,0 24,12 12,24 0,12" fill="#10B981"/>
</svg>
"@

# --- Game Logic Templates ---

$HealthComponentCode = @"
# TemplateVersion: $TemplateVersion
extends Node
class_name HealthComponent

signal health_changed(current_health, max_health)
signal died

@export var max_health: float = 100.0
var current_health: float

func _ready() -> void:
    current_health = max_health

func take_damage(amount: float) -> void:
    if not multiplayer.is_server(): return
    current_health -= amount
    health_changed.emit(current_health, max_health)
    if current_health <= 0: died.emit()
"@

$BasePlayerCode = @"
# TemplateVersion: $TemplateVersion
class_name BasePlayer
extends CharacterBody2D

@export var speed: float = 300.0

func _enter_tree() -> void:
    set_multiplayer_authority(name.to_int())

func _physics_process(_delta: float) -> void:
    if not is_multiplayer_authority(): return
    var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if direction != Vector2.ZERO:
        rotation = direction.angle()
        velocity = direction * speed
    else:
        velocity = Vector2.ZERO
    move_and_slide()
"@

$BaseEnemyCode = @"
# TemplateVersion: $TemplateVersion
class_name BaseEnemy
extends CharacterBody2D

@export var speed: float = 100.0
var target_node: Node2D = null

func _physics_process(_delta: float) -> void:
    if not multiplayer.is_server(): return
    if target_node == null or not is_instance_valid(target_node):
        var players = get_tree().get_nodes_in_group("players")
        if players.size() > 0: target_node = players[0] 
        return
    var direction = (target_node.global_position - global_position).normalized()
    rotation = direction.angle()
    velocity = direction * speed
    move_and_slide()
"@

$BaseTowerCode = @"
# TemplateVersion: $TemplateVersion
class_name BaseTower
extends StaticBody2D

@export var fire_rate: float = 1.0 
var enemies_in_range: Array[Node2D] = []
var fire_timer: float = 0.0

func _physics_process(delta: float) -> void:
    if not multiplayer.is_server(): return
    fire_timer -= delta
    enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e))
    if enemies_in_range.size() > 0 and fire_timer <= 0:
        print("Tower firing at ", enemies_in_range[0].name)
        fire_timer = 1.0 / fire_rate

func _on_range_body_entered(body: Node2D) -> void:
    if body is BaseEnemy: enemies_in_range.append(body)

func _on_range_body_exited(body: Node2D) -> void:
    if body in enemies_in_range: enemies_in_range.erase(body)
"@

$WaveManagerCode = @"
# TemplateVersion: $TemplateVersion
extends Node

@export var spawn_interval: float = 2.0
var spawn_timer: float = 0.0
var base_enemy_scene = preload("res://entities/enemies/base_enemy/base_enemy.tscn")

func _process(delta: float) -> void:
    if not multiplayer.is_server(): return
    spawn_timer -= delta
    if spawn_timer <= 0:
        var enemy = base_enemy_scene.instantiate()
        enemy.global_position = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 1000
        spawn_timer = spawn_interval
"@

$NetworkManagerCode = @"
# TemplateVersion: $TemplateVersion
extends Node

const PORT = 7000
const MAX_PLAYERS = 4

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal server_disconnected

func host_game() -> bool:
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(PORT, MAX_PLAYERS)
    if error != OK: return false
    multiplayer.multiplayer_peer = peer
    return true

func join_game(address: String) -> void:
    var peer = ENetMultiplayerPeer.new()
    peer.create_client(address, PORT)
    multiplayer.multiplayer_peer = peer
"@

$EventBusCode = @"
# TemplateVersion: $TemplateVersion
extends Node

signal enemy_died(enemy_position: Vector2)
signal player_took_damage(player_id: int, new_health: float)
signal exp_gem_collected(amount: int, player_id: int)
signal wave_completed(wave_number: int)
"@

$GameStateCode = @"
# TemplateVersion: $TemplateVersion
extends Node

var current_wave: int = 1
var global_gold: int = 0
var players_alive: int = 0
"@

$InventoryCode = @"
# TemplateVersion: $TemplateVersion
extends Node
class_name InventoryComponent

signal inventory_updated(items)
@export var max_capacity: int = 10
var items: Array[String] = []

func add_item(item_id: String) -> bool:
    if not multiplayer.is_server(): return false
    if items.size() < max_capacity:
        items.append(item_id)
        inventory_updated.emit(items)
        return true
    return false
"@

$ExpGemManagerCode = @"
# TemplateVersion: $TemplateVersion
extends Node

@export var gem_scene: PackedScene

func _ready() -> void:
    if multiplayer.is_server(): pass

func _spawn_gem_at_location(pos: Vector2) -> void:
    if gem_scene == null: return
    var gem = gem_scene.instantiate()
    gem.global_position = pos
    call_deferred("add_child", gem)
"@

$LootDropManagerCode = @"
# TemplateVersion: $TemplateVersion
extends Node

func roll_for_loot(enemy_type: String) -> String:
    var roll = randf()
    if roll > 0.95: return "rare_weapon"
    elif roll > 0.8: return "health_potion"
    else: return "none"
"@

$LobbyStagingCode = @"
# TemplateVersion: $TemplateVersion
extends Control

# Note: Escaped node path references for PowerShell Here-Strings
@onready var player_list: ItemList = get_node("MarginContainer/VBoxContainer/PlayerList")
@onready var start_button: Button = get_node("MarginContainer/VBoxContainer/StartButton")
@onready var status_label: Label = get_node("MarginContainer/VBoxContainer/StatusLabel")

const MAIN_LEVEL_PATH = "res://levels/map_01_graveyard/map_01_graveyard.tscn"

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    
    if multiplayer.is_server():
        status_label.text = "Hosting Game. Waiting for players..."
        start_button.visible = true
        start_button.pressed.connect(_on_start_button_pressed)
    else:
        status_label.text = "Connected! Waiting for host..."
        start_button.visible = false
        
    _update_player_list()

func _on_peer_connected(id: int) -> void: _update_player_list()
func _on_peer_disconnected(id: int) -> void: _update_player_list()
func _on_server_disconnected() -> void: get_tree().change_scene_to_file("res://ui/multiplayer_menus/host_join_screen/host_join_screen.tscn")

func _update_player_list() -> void:
    if player_list == null: return
    player_list.clear()
    var my_text = "Player " + str(multiplayer.get_unique_id()) + " (You)"
    if multiplayer.is_server(): my_text += " [HOST]"
    player_list.add_item(my_text)
    for peer_id in multiplayer.get_peers():
        player_list.add_item("Player " + str(peer_id))

func _on_start_button_pressed() -> void:
    if multiplayer.is_server(): _start_game.rpc()

@rpc("call_local", "authority", "reliable")
func _start_game() -> void:
    get_tree().change_scene_to_file(MAIN_LEVEL_PATH)
"@

# --- File Layout Mapping ---
$directories = @(
    "assets/audio", "assets/fonts", "assets/textures",
    "components", "core/network",
    "entities/enemies/base_enemy", "entities/enemies/elite_brute", "entities/enemies/zombie_swarm",
    "entities/player/base_player", "entities/player/player_state_sync", "entities/player/weapons",
    "entities/towers/aura_trap", "entities/towers/ballista", "entities/towers/base_tower",
    "levels/base_level", "levels/map_01_graveyard",
    "systems/exp_gem", "systems/loot_drop",
    "ui/hud", "ui/menus", "ui/multiplayer_menus/host_join_screen", "ui/multiplayer_menus/lobby_staging"
)

$files = @(
    [PSCustomObject]@{ Path = "assets/textures/player.svg"; Content = $SvgPlayer }
    [PSCustomObject]@{ Path = "assets/textures/enemy.svg"; Content = $SvgEnemy }
    [PSCustomObject]@{ Path = "assets/textures/tower.svg"; Content = $SvgTower }
    [PSCustomObject]@{ Path = "assets/textures/exp_gem.svg"; Content = $SvgGem }

    [PSCustomObject]@{ Path = "components/health_component.gd"; Content = $HealthComponentCode }
    [PSCustomObject]@{ Path = "components/hitbox_component.tscn"; Content = (Get-SceneContent -NodeName "HitboxComponent" -NodeType "Area2D") }
    [PSCustomObject]@{ Path = "components/hurtbox_component.tscn"; Content = (Get-SceneContent -NodeName "HurtboxComponent" -NodeType "Area2D") }
    [PSCustomObject]@{ Path = "components/inventory.gd"; Content = $InventoryCode }

    [PSCustomObject]@{ Path = "core/event_bus.gd"; Content = $EventBusCode }
    [PSCustomObject]@{ Path = "core/game_state.gd"; Content = $GameStateCode }
    [PSCustomObject]@{ Path = "core/wave_manager.gd"; Content = $WaveManagerCode }
    [PSCustomObject]@{ Path = "core/network/network_manager.gd"; Content = $NetworkManagerCode }
    [PSCustomObject]@{ Path = "core/network/lan_broadcaster.gd"; Content = "# TemplateVersion: $TemplateVersion`nextends Node`n" }
    [PSCustomObject]@{ Path = "core/network/lan_listener.gd"; Content = "# TemplateVersion: $TemplateVersion`nextends Node`n" }

    [PSCustomObject]@{ Path = "entities/player/base_player/base_player.tscn"; Content = (Get-SceneContent -NodeName "BasePlayer" -NodeType "CharacterBody2D") }
    [PSCustomObject]@{ Path = "entities/player/base_player/base_player.gd"; Content = $BasePlayerCode }
    [PSCustomObject]@{ Path = "entities/player/player_state_sync/player_state_sync.gd"; Content = "# TemplateVersion: $TemplateVersion`nextends MultiplayerSynchronizer`n" }
    [PSCustomObject]@{ Path = "entities/enemies/base_enemy/base_enemy.tscn"; Content = (Get-SceneContent -NodeName "BaseEnemy" -NodeType "CharacterBody2D") }
    [PSCustomObject]@{ Path = "entities/enemies/base_enemy/base_enemy.gd"; Content = $BaseEnemyCode }
    [PSCustomObject]@{ Path = "entities/towers/base_tower/base_tower.tscn"; Content = (Get-SceneContent -NodeName "BaseTower" -NodeType "StaticBody2D") }
    [PSCustomObject]@{ Path = "entities/towers/base_tower/base_tower.gd"; Content = $BaseTowerCode }

    [PSCustomObject]@{ Path = "ui/hud/hud.tscn"; Content = (Get-SceneContent -NodeName "HUD" -NodeType "CanvasLayer") }
    [PSCustomObject]@{ Path = "ui/multiplayer_menus/host_join_screen/host_join_screen.tscn"; Content = (Get-SceneContent -NodeName "HostJoinScreen" -NodeType "Control") }
    [PSCustomObject]@{ Path = "ui/multiplayer_menus/lobby_staging/lobby_staging.tscn"; Content = (Get-SceneContent -NodeName "LobbyStaging" -NodeType "Control") }
    [PSCustomObject]@{ Path = "ui/multiplayer_menus/lobby_staging/lobby_staging.gd"; Content = $LobbyStagingCode }
    
    [PSCustomObject]@{ Path = "systems/exp_gem/exp_gem_manager.gd"; Content = $ExpGemManagerCode }
    [PSCustomObject]@{ Path = "systems/loot_drop/loot_drop_manager.gd"; Content = $LootDropManagerCode }
)

# --- Godot Plugin Downloader ---
function Install-GodotPlugin {
    param([string]$DownloadUrl, [string]$PluginName, [string]$BasePath)

    $targetAddonPath = Join-Path -Path $BasePath -ChildPath "addons\$PluginName"
    if (Test-Path -Path $targetAddonPath) {
        Write-Host "[~] Plugin Exists:   $PluginName (Skipped)" -ForegroundColor DarkGray
        return
    }

    Write-Host "[>] Downloading:     $PluginName..." -ForegroundColor Blue
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "GodotScaffold_$(New-Guid)"
    $zipPath = Join-Path -Path $tempDir -ChildPath "$PluginName.zip"
    
    try {
        $null = New-Item -Path $tempDir -ItemType Directory -Force
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        
        $extractedAddonPath = Get-ChildItem -Path $tempDir -Recurse -Directory | 
                              Where-Object { $_.Name -eq $PluginName -and $_.Parent.Name -eq "addons" } | 
                              Select-Object -First 1

        if ($extractedAddonPath) {
            $localAddonsDir = Join-Path -Path $BasePath -ChildPath "addons"
            if (-not (Test-Path -Path $localAddonsDir)) { $null = New-Item -Path $localAddonsDir -ItemType Directory -Force }
            Move-Item -Path $extractedAddonPath.FullName -Destination $targetAddonPath -Force
            Write-Host "[+] Plugin Installed: $PluginName" -ForegroundColor Green
        } else {
            Write-Host "[!] Failed to locate 'addons/$($PluginName)' inside the downloaded archive." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[!] Download/Extraction failed for $($PluginName): $_" -ForegroundColor Red
    }
    finally {
        if (Test-Path -Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
    }
}

Write-Verbose "Starting Godot project scaffolding at destination: $BasePath"

# --- Execute Directory Creation ---
foreach ($dir in $directories) {
    $normalizedDir = $dir -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $targetPath = Join-Path -Path $BasePath -ChildPath $normalizedDir
    if (-not (Test-Path -Path $targetPath)) {
        $null = New-Item -Path $targetPath -ItemType Directory -Force
        Write-Host "[+] Directory Created: $dir" -ForegroundColor Green
    }
}

# --- Execute File Injection & Version Control ---
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

foreach ($file in $files) {
    $normalizedFile = $file.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $targetPath = Join-Path -Path $BasePath -ChildPath $normalizedFile

    if (Test-Path -Path $targetPath) {
        $existingContent = Get-Content -Path $targetPath -Raw
        $regexPattern = "TemplateVersion\s*[:=]\s*`"?$($TemplateVersion.Replace('.', '\.'))`"?"
        
        if ($existingContent -match $regexPattern) {
            Write-Host "[~] Version Match:   $($file.Path) (Skipped)" -ForegroundColor DarkGray
            continue
        } else {
            Write-Host "[!] Version Mismatch: Overwriting $($file.Path)" -ForegroundColor Magenta
        }
    }

    [System.IO.File]::WriteAllText($targetPath, $file.Content, $utf8NoBom)
    if (-not (Test-Path -Path $targetPath)) {
        Write-Host "[*] File Injected:   $($file.Path)" -ForegroundColor Cyan
    }
}

# --- Execute Plugin Installations ---
Write-Host "`nInitializing automated plugin deployment..." -ForegroundColor Yellow

foreach ($plugin in $PluginsToInstall) {
    Install-GodotPlugin -DownloadUrl $plugin.Url -PluginName $plugin.Name -BasePath $BasePath
}

Write-Host "`nScaffolding complete. Target schema version: v$TemplateVersion" -ForegroundColor Yellow