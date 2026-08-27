/// The display state of a workspace's discovered translation-model inventory.
///
/// Workspaces own discovery and selection behavior; this shared state keeps
/// their picker presentation consistent without tying it to a provider.
enum ModelInventoryStatus { initial, loading, ready, empty, unavailable }
