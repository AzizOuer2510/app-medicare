package com.medicare.roles;
import com.medicare.common.ApiException;
import com.medicare.security.account.*;
import com.medicare.user.entity.*;
import com.medicare.user.repository.UserRepository;
import java.time.Instant;
import java.util.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service @RequiredArgsConstructor
public class RoleChangeService {
    private final RoleChangeRepository requests;
    private final AccountAccess accounts;
    private final UserRepository users;
    private final SecurityAudit audit;
    public record View(Long id, Long userId, String fullName, String email, Role previousRole, Role requestedRole,
                       RoleChangeRequest.Status status, String reason, Instant requestedAt, Long reviewerId, Instant reviewedAt, String decisionNote) {}
    public View view(RoleChangeRequest r) {
        var user = users.findById(r.getUserId()).orElseThrow();
        return new View(r.getId(), r.getUserId(), user.getFullName(), user.getEmail(), r.getPreviousRole(), r.getRequestedRole(),
                r.getStatus(), r.getReason(), r.getRequestedAt(), r.getReviewerId(), r.getReviewedAt(), r.getDecisionNote());
    }
    @Transactional
    public View request(User actor, Role requested, String reason) {
        User user = accounts.lock(actor.getId());
        if (user.getRole() == requested) throw new ApiException(HttpStatus.CONFLICT, "ROLE_ALREADY_ASSIGNED");
        if (requested == Role.DOCTOR && user.getRole() == Role.USER) {
            user.setRole(Role.DOCTOR);
            AccountAccess.revoke(user);
            var request = new RoleChangeRequest();
            request.setUserId(user.getId());
            request.setPreviousRole(Role.USER);
            request.setRequestedRole(Role.DOCTOR);
            request.setStatus(RoleChangeRequest.Status.APPROVED);
            request.setReason(reason);
            request.setRequestedAt(Instant.now());
            request.setReviewedAt(request.getRequestedAt());
            request.setDecisionNote("Rôle médecin attribué automatiquement.");
            audit.record(null, user.getId(), "ROLE_AUTO_GRANTED",
                    "Doctor role granted automatically; no manual approval required");
            return view(requests.save(request));
        }
        if (requests.existsByUserIdAndStatus(user.getId(), RoleChangeRequest.Status.PENDING)) {
            throw new ApiException(HttpStatus.CONFLICT, "ROLE_REQUEST_PENDING");
        }
        var r = new RoleChangeRequest(); r.setUserId(user.getId()); r.setPreviousRole(user.getRole());
        r.setRequestedRole(requested); r.setStatus(RoleChangeRequest.Status.PENDING); r.setReason(reason);
        r.setRequestedAt(Instant.now()); requests.save(r);
        audit.record(user.getId(), user.getId(), "ROLE_REQUESTED", requested.name() + ": " + reason);
        return view(r);
    }
    @Transactional
    public View decide(Long id, User admin, boolean approve, String note) {
        var r = requests.findForUpdate(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Request not found"));
        if (r.getStatus() != RoleChangeRequest.Status.PENDING) throw new ApiException(HttpStatus.CONFLICT, "REQUEST_ALREADY_REVIEWED");
        if (r.getUserId().equals(admin.getId())) throw new ApiException(HttpStatus.FORBIDDEN, "SELF_APPROVAL_FORBIDDEN");
        User user = accounts.lock(r.getUserId());
        if (approve && (!user.isEmailVerified() || user.getMergedIntoId() != null || user.isPasswordResetRequired())) {
            throw new ApiException(HttpStatus.CONFLICT, "ACCOUNT_REQUIRES_VERIFICATION");
        }
        if (approve && user.getRole() != r.getPreviousRole()) throw new ApiException(HttpStatus.CONFLICT, "ROLE_CHANGED_SINCE_REQUEST");
        if (approve) { user.setRole(r.getRequestedRole()); AccountAccess.revoke(user); }
        r.setStatus(approve ? RoleChangeRequest.Status.APPROVED : RoleChangeRequest.Status.REJECTED);
        r.setReviewerId(admin.getId()); r.setReviewedAt(Instant.now()); r.setDecisionNote(note);
        audit.record(admin.getId(), user.getId(), approve ? "ROLE_APPROVED" : "ROLE_REJECTED", "Request " + id + ": " + note);
        return view(r);
    }

    @Transactional
    public int autoGrantPendingDoctorRequests() {
        int resolved = 0;
        var candidates = requests.findByStatusAndRequestedRoleOrderByRequestedAtAsc(
                RoleChangeRequest.Status.PENDING, Role.DOCTOR);
        for (var candidate : candidates) {
            var request = requests.findForUpdate(candidate.getId()).orElse(null);
            if (request == null || request.getStatus() != RoleChangeRequest.Status.PENDING) continue;

            var user = users.findByIdForUpdate(request.getUserId()).orElse(null);
            boolean grant = user != null && user.getRole() == Role.USER
                    && user.getMergedIntoId() == null && !user.isPasswordResetRequired();
            boolean alreadyDoctor = user != null && user.getRole() == Role.DOCTOR;
            if (grant) {
                user.setRole(Role.DOCTOR);
                AccountAccess.revoke(user);
                request.setStatus(RoleChangeRequest.Status.APPROVED);
                request.setDecisionNote("Rôle médecin attribué automatiquement.");
                audit.record(null, user.getId(), "ROLE_AUTO_GRANTED",
                        "Pending doctor role request granted automatically");
            } else if (alreadyDoctor) {
                request.setStatus(RoleChangeRequest.Status.APPROVED);
                request.setDecisionNote("Compte déjà médecin ; demande clôturée automatiquement.");
            } else {
                request.setStatus(RoleChangeRequest.Status.REJECTED);
                request.setDecisionNote("Demande clôturée automatiquement car le compte n’est plus éligible.");
                audit.record(null, request.getUserId(), "ROLE_AUTO_CLOSED",
                        "Pending doctor role request closed because account is no longer eligible");
            }
            request.setReviewerId(null);
            request.setReviewedAt(Instant.now());
            requests.save(request);
            resolved++;
        }
        return resolved;
    }

    @Transactional(readOnly = true)
    public List<View> own(Long userId) { return requests.findByUserIdOrderByRequestedAtDesc(userId).stream().map(this::view).toList(); }
    @Transactional(readOnly = true)
    public List<View> pending() { return requests.findByStatusOrderByRequestedAtAsc(RoleChangeRequest.Status.PENDING).stream().map(this::view).toList(); }
}
