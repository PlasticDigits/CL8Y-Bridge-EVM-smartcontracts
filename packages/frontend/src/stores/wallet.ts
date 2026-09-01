/**
 * Wallet State Management for CL8Y Bridge
 * 
 * Uses Zustand for lightweight, hook-based state management.
 * Handles wallet connection state for Terra Classic wallets.
 */

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import {
  connectTerraWallet,
  disconnectTerraWallet,
  isStationInstalled,
  isKeplrInstalled,
  isLeapInstalled,
  isCosmostationInstalled,
  connectDevWallet,
  tryReconnect,
  WalletName,
  WalletType,
  TerraWalletType,
} from '../services/terra';
import { NETWORKS, DEFAULT_NETWORK } from '../utils/constants';
import { useWalletConnectPairingStore } from './walletConnectPairing';

// Re-export for convenience
export { WalletName, WalletType };
export type { TerraWalletType };

/**
 * Thrown when Cancel / disconnect wins the race against an in-flight
 * `connectTerraWallet`. Not a user-facing error — callers must not map it to
 * “install the extension” or leave it as `connectionError`.
 */
export class ConnectionCancelledError extends Error {
  constructor() {
    super('Connection cancelled')
    this.name = 'ConnectionCancelledError'
  }
}

export function isConnectionCancelledError(error: unknown): boolean {
  return error instanceof ConnectionCancelledError
}

type WalletHydrateResetTarget = Pick<
  WalletState,
  'connecting' | 'connectingWallet' | 'connectingSince' | 'showWalletModal' | 'connectionError'
>

/**
 * INV-FE-WC-MOBILE-1: never leave a spinner-disabled CTA after persist hydrate.
 * `connecting` is not in `partialize`; this still clears older persisted shapes
 * and in-memory leftovers from a previous tab.
 */
export function applyWalletHydrateReset(state: WalletHydrateResetTarget): void {
  state.connecting = false
  state.connectingWallet = null
  state.connectingSince = null
  state.showWalletModal = false
  state.connectionError = null
}

/** Bumped on connect start, Cancel, and disconnect so late WC success cannot reconnect. */
let connectEpoch = 0

function bumpConnectEpoch(): void {
  connectEpoch += 1
}

/**
 * INV-FE-WC-MOBILE-1: a cancelled `connectTerraWallet` may already have written
 * into `connectedWallets`. Drop that ghost session only when no newer
 * `connect()` owns the shared WalletConnect client.
 *
 * Cosmes `KeplrController.disconnect` calls `this.wc.disconnect()` when the
 * controller map is empty. Modal Retry does `cancelConnection()` then
 * `connect()`; the in-flight Retry must keep that singleton. Skip protocol
 * disconnect when `connecting` is true. Always withhold `connected: true`.
 */
export function shouldDisconnectGhostWalletConnect(connecting: boolean): boolean {
  return !connecting
}

async function disconnectGhostWalletConnectIfUnowned(
  get: () => WalletState
): Promise<void> {
  if (!shouldDisconnectGhostWalletConnect(get().connecting)) {
    return
  }
  try {
    await disconnectTerraWallet()
  } catch (e) {
    console.error('Disconnect after cancelled connect (non-fatal):', e)
  }
}

/** Map TerraWalletType (persisted string) back to cosmes WalletName for reconnection */
const WALLET_TYPE_TO_NAME: Record<TerraWalletType, WalletName> = {
  station: WalletName.STATION,
  keplr: WalletName.KEPLR,
  luncdash: WalletName.LUNCDASH,
  galaxy: WalletName.GALAXYSTATION,
  leap: WalletName.LEAP,
  cosmostation: WalletName.COSMOSTATION,
};

export interface WalletState {
  // Connection state
  connected: boolean;
  connecting: boolean;
  address: string | null;
  walletType: TerraWalletType | null;
  connectionType: WalletType | null;
  
  // Network state
  chainId: string | null;
  
  // Balances (micro units)
  luncBalance: string;
  
  // Connecting state for specific wallets
  connectingWallet: WalletName | null;
  /** Timestamp when connecting started, used to detect stale WalletConnect attempts */
  connectingSince: number | null;
  
  // Connection error (displayed in wallet modal)
  connectionError: string | null;
  
  // Modal state (for triggering wallet modal from other components)
  showWalletModal: boolean;
  
  // Actions
  connect: (walletName: WalletName, walletType?: WalletType) => Promise<void>;
  connectSimulated: () => void;
  disconnect: () => Promise<void>;
  attemptReconnect: () => Promise<boolean>;
  setBalances: (balances: { lunc?: string }) => void;
  setConnecting: (connecting: boolean) => void;
  cancelConnection: () => void;
  clearConnectionError: () => void;
  setShowWalletModal: (show: boolean) => void;
}

// Wallet availability checks
export function checkWalletAvailability() {
  return {
    station: isStationInstalled(),
    keplr: isKeplrInstalled(),
    leap: isLeapInstalled(),
    cosmostation: isCosmostationInstalled(),
    // WalletConnect-only wallets are always "available"
    luncdash: true,
    galaxy: true,
  };
}

export const useWalletStore = create<WalletState>()(
  persist(
    (set, get) => ({
      // Initial state
      connected: false,
      connecting: false,
      address: null,
      walletType: null,
      connectionType: null,
      chainId: null,
      luncBalance: '0',
      connectingWallet: null,
      connectingSince: null,
      connectionError: null,
      showWalletModal: false,

      // Connect dev wallet (DEV_MODE only) using cosmes MnemonicWallet
      connectSimulated: () => {
        const result = connectDevWallet()
        const chainId = NETWORKS[DEFAULT_NETWORK as keyof typeof NETWORKS].terra.chainId
        set({
          connected: true,
          connecting: false,
          connectingWallet: null,
          connectingSince: null,
          address: result.address,
          walletType: result.walletType as TerraWalletType,
          connectionType: result.connectionType,
          chainId,
          luncBalance: '0',
        })
      },

      // Connect to wallet
      connect: async (walletName: WalletName, walletTypeParam: WalletType = WalletType.EXTENSION) => {
        const epoch = ++connectEpoch
        set({ connecting: true, connectingWallet: walletName, connectingSince: Date.now(), connectionError: null });
        
        try {
          const effectiveWalletType = walletName === WalletName.LUNCDASH 
            ? WalletType.WALLETCONNECT 
            : walletTypeParam;
          
          const result = await connectTerraWallet(walletName, effectiveWalletType);
          if (epoch !== connectEpoch) {
            await disconnectGhostWalletConnectIfUnowned(get)
            throw new ConnectionCancelledError()
          }
          const chainId = NETWORKS[DEFAULT_NETWORK as keyof typeof NETWORKS].terra.chainId
          
          set({
            connected: true,
            connecting: false,
            connectingWallet: null,
            connectingSince: null,
            connectionError: null,
            address: result.address,
            walletType: result.walletType,
            connectionType: result.connectionType,
            chainId,
          });
          
          console.log('Terra wallet connected:', result.address, result.walletType);
        } catch (error) {
          if (isConnectionCancelledError(error) || epoch !== connectEpoch) {
            throw isConnectionCancelledError(error) ? error : new ConnectionCancelledError()
          }
          const message = error instanceof Error ? error.message : 'Connection failed';
          console.error('Wallet connection failed:', error);
          set({ connecting: false, connectingWallet: null, connectingSince: null, connectionError: message });
          throw error;
        }
      },

      // Attempt to silently reconnect a previously-connected wallet (e.g. page refresh).
      // Extensions re-request key; WalletConnect restores cached session.
      attemptReconnect: async () => {
        const { walletType, connectionType, address } = get()
        if (!walletType || !address) return false

        const walletName = WALLET_TYPE_TO_NAME[walletType]
        if (!walletName) return false

        const effectiveType = connectionType ?? WalletType.EXTENSION

        try {
          const result = await tryReconnect(walletName, effectiveType)
          if (result) {
            const chainId = NETWORKS[DEFAULT_NETWORK as keyof typeof NETWORKS].terra.chainId
            set({
              connected: true,
              address: result.address,
              chainId,
            })
            return true
          }
        } catch (error) {
          console.warn('Auto-reconnect failed:', error)
        }

        // Clear persisted state on failed reconnection
        set({
          connected: false,
          address: null,
          walletType: null,
          connectionType: null,
          chainId: null,
        })
        return false
      },

      // Disconnect wallet
      disconnect: async () => {
        bumpConnectEpoch()
        try {
          await disconnectTerraWallet();
        } catch (e) {
          console.error('Disconnect error (non-fatal):', e);
        }
        
        set({
          connected: false,
          connecting: false,
          connectingWallet: null,
          connectingSince: null,
          address: null,
          walletType: null,
          connectionType: null,
          chainId: null,
          luncBalance: '0',
        });
      },

      // Update balances
      setBalances: (balances) => {
        set((state) => ({
          luncBalance: balances.lunc ?? state.luncBalance,
        }));
      },

      // Set connecting state
      setConnecting: (connecting) => {
        set({ connecting });
      },

      // Cancel pending connection and any mobile WalletConnect pairing sheet.
      // Bump epoch so a late `connectTerraWallet` resolve cannot set connected.
      cancelConnection: () => {
        bumpConnectEpoch();
        useWalletConnectPairingStore.getState().close();
        set({ connecting: false, connectingWallet: null, connectingSince: null, connectionError: null });
      },

      // Clear connection error (e.g. when user dismisses or retries)
      clearConnectionError: () => {
        set({ connectionError: null });
      },

      // Control wallet modal visibility
      setShowWalletModal: (show: boolean) => {
        set({ showWalletModal: show });
      },
    }),
    {
      name: 'cl8y-bridge-wallet-storage',
      partialize: (state) => ({
        walletType: state.walletType,
        connectionType: state.connectionType,
        address: state.address,
      }),
      // INV-FE-WC-MOBILE-1: connecting is never persisted; force a clean CTA on hydrate
      // so a previous tab's spinner cannot disable Connect on a fresh visit.
      onRehydrateStorage: () => (state) => {
        if (!state) return
        applyWalletHydrateReset(state)
      },
    }
  )
);
