import { assertAmount } from '../models/Ledger';
/**
 * DAO Governance — KDEX-weighted proposals & voting.
 * 1 KDEX = 1 vote. The DAO is "earned": the platform starts centralized and
 * hands over parameters as the community demonstrates it can govern them.
 */

import { KarmaDexLedger } from '../models/Tokens';

export enum ProposalStatus {
  OPEN = 'open',
  PASSED = 'passed',
  REJECTED = 'rejected',
}

export interface Proposal {
  id: string;
  title: string;
  description: string;
  createdBy: string;
  createdAt: Date;
  closesAt: Date;
  votesFor: number; // KDEX weight
  votesAgainst: number; // KDEX weight
  voters: Set<string>;
  status: ProposalStatus;
  quorum: number; // minimum total KDEX weight to be valid
}

export class Governance {
  proposals: Map<string, Proposal> = new Map();

  private snapshots = new Map<string, Map<string, number>>();

  constructor(private kdexLedger: KarmaDexLedger) {}

  createProposal(
    id: string,
    title: string,
    description: string,
    createdBy: string,
    durationMs: number,
    quorum: number,
    now: Date = new Date()
  ): Proposal {
    if (!id || this.proposals.has(id)) throw new Error("duplicate or missing proposal id");
    assertAmount(durationMs, true); assertAmount(quorum, true);
    if (!Number.isFinite(now.getTime())) throw new Error("invalid proposal date");
    this.snapshots.set(id, new Map([...this.kdexLedger.balances].map(([user, b]) => [user, b.balance])));
    const proposal: Proposal = {
      id,
      title,
      description,
      createdBy,
      createdAt: now,
      closesAt: new Date(now.getTime() + durationMs),
      votesFor: 0,
      votesAgainst: 0,
      voters: new Set(),
      status: ProposalStatus.OPEN,
      quorum,
    };
    this.proposals.set(id, proposal);
    return structuredClone(proposal);
  }

  /**
   * Cast a vote weighted by the voter's KDEX balance. One vote per address per
   * proposal. Reputation (KRUNE) intentionally does NOT vote — governance is a
   * capital-and-belief function, kept separate from the behavioral layer.
   */
  vote(proposalId: string, voterId: string, support: boolean, now: Date = new Date()): {
    ok: boolean;
    reason?: string;
  } {
    const p = this.proposals.get(proposalId);
    if (!p) return { ok: false, reason: 'proposal not found' };
    if (p.status !== ProposalStatus.OPEN) return { ok: false, reason: 'proposal closed' };
    if (!Number.isFinite(now.getTime()) || now < p.createdAt) return { ok: false, reason: "invalid voting time" };
    if (now >= p.closesAt) return { ok: false, reason: 'voting period ended' };
    if (p.voters.has(voterId)) return { ok: false, reason: 'already voted' };

    const weight = this.snapshots.get(proposalId)?.get(voterId) ?? 0;
    if (weight <= 0) return { ok: false, reason: 'no KDEX voting power' };

    if (support) p.votesFor += weight;
    else p.votesAgainst += weight;
    p.voters.add(voterId);

    return { ok: true };
  }

  /** Tally after close. Requires quorum; simple majority passes. */
  finalize(proposalId: string, now: Date = new Date()): ProposalStatus {
    const p = this.proposals.get(proposalId);
    if (!p) throw new Error('proposal not found');
    if (now < p.closesAt) throw new Error('voting still open');

    const total = p.votesFor + p.votesAgainst;
    if (total < p.quorum) {
      p.status = ProposalStatus.REJECTED; // failed quorum
    } else if (p.votesFor > p.votesAgainst) {
      p.status = ProposalStatus.PASSED;
    } else {
      p.status = ProposalStatus.REJECTED;
    }
    return p.status;
  }
}
