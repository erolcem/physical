"""Friends / social (PDF Part 6). Add by email → pending request → accept →
compare overall ranks. Only accepted friends see each other's overall rank (never
raw samples) — privacy by mutual consent."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, delete, or_, select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..models import Friendship, Sample, User
from ..ranking import compute_ranks
from ..schemas import FriendOut, FriendRequestIn, GroupRank, PendingFriendOut

router = APIRouter(prefix="/me/friends", tags=["friends"])


def _overall_rank(db: Session, user_id: str) -> GroupRank | None:
    """A user's overall rank from their samples, or None if they have no data."""
    samples = list(db.scalars(select(Sample).where(Sample.user_id == user_id)))
    if not samples:
        return None
    overall, _, _ = compute_ranks(samples)
    return GroupRank(**overall)


def _link(db: Session, a: str, b: str) -> Friendship | None:
    """The friendship row between a and b in either direction, if any."""
    return db.scalar(select(Friendship).where(or_(
        and_(Friendship.requester_id == a, Friendship.addressee_id == b),
        and_(Friendship.requester_id == b, Friendship.addressee_id == a))))


@router.post("")
def add_friend(body: FriendRequestIn,
               user_id: str = Depends(current_user),
               db: Session = Depends(get_db)):
    """Send a friend request by email. Idempotent: returns the existing status if
    a link already exists."""
    target = db.scalar(select(User).where(User.email == body.email.strip()))
    if target is None:
        raise HTTPException(404, "No account with that email")
    if target.id == user_id:
        raise HTTPException(400, "You can't add yourself")
    existing = _link(db, user_id, target.id)
    if existing is not None:
        return {"status": existing.status, "friend_id": target.id}
    db.add(Friendship(requester_id=user_id, addressee_id=target.id, status="pending"))
    db.commit()
    return {"status": "pending", "friend_id": target.id}


@router.get("", response_model=list[FriendOut])
def list_friends(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """Accepted friends with their overall rank (a mini leaderboard)."""
    rows = db.scalars(select(Friendship).where(and_(
        Friendship.status == "accepted",
        or_(Friendship.requester_id == user_id,
            Friendship.addressee_id == user_id))))
    out = []
    for f in rows:
        other = f.addressee_id if f.requester_id == user_id else f.requester_id
        u = db.get(User, other)
        out.append(FriendOut(user_id=other, email=u.email if u else None,
                             name=u.name if u else None,
                             rank=_overall_rank(db, other)))
    return out


@router.get("/requests", response_model=list[PendingFriendOut])
def pending_requests(user_id: str = Depends(current_user),
                     db: Session = Depends(get_db)):
    """Incoming requests awaiting my acceptance."""
    rows = db.scalars(select(Friendship).where(and_(
        Friendship.addressee_id == user_id, Friendship.status == "pending")))
    out = []
    for f in rows:
        u = db.get(User, f.requester_id)
        out.append(PendingFriendOut(requester_id=f.requester_id,
                                    email=u.email if u else None))
    return out


@router.post("/{requester_id}/accept")
def accept_request(requester_id: str,
                   user_id: str = Depends(current_user),
                   db: Session = Depends(get_db)):
    f = db.scalar(select(Friendship).where(and_(
        Friendship.requester_id == requester_id,
        Friendship.addressee_id == user_id,
        Friendship.status == "pending")))
    if f is None:
        raise HTTPException(404, "No pending request from that user")
    f.status = "accepted"
    db.commit()
    return {"status": "accepted"}


@router.delete("/{other_id}")
def remove_friend(other_id: str,
                  user_id: str = Depends(current_user),
                  db: Session = Depends(get_db)):
    """Remove a friend or decline/cancel a request (either direction)."""
    db.execute(delete(Friendship).where(or_(
        and_(Friendship.requester_id == user_id, Friendship.addressee_id == other_id),
        and_(Friendship.requester_id == other_id, Friendship.addressee_id == user_id))))
    db.commit()
    return {"removed": True}
