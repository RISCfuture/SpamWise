import Foundation
import SpamWiseCore

/// Holds a store's cross-process transaction lock, as another process in a long transaction does.
final class StoreLock {
  private let descriptor: Int32
  private var isHeld = true

  /// Takes `store`'s lock, failing when another holder already has it.
  init(_ store: Store) throws {
    descriptor = unsafe open(store.url.path + ".lock", O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw POSIXError(.EBADF) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw POSIXError(.EWOULDBLOCK)
    }
  }

  /// Lets transactions run again.
  func release() {
    guard isHeld else { return }
    isHeld = false
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }

  deinit { release() }
}
