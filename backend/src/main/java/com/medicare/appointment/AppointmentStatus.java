package com.medicare.appointment;

public enum AppointmentStatus {
    PLANNED,
    CONFIRMED,
    COMPLETED,
    CANCELLED;

    public boolean isTerminal() {
        return this == COMPLETED || this == CANCELLED;
    }

    public boolean canTransitionTo(AppointmentStatus next) {
        if (this == next) {
            return true;
        }
        return switch (this) {
            case PLANNED -> next == CONFIRMED || next == COMPLETED || next == CANCELLED;
            case CONFIRMED -> next == COMPLETED || next == CANCELLED;
            case COMPLETED, CANCELLED -> false;
        };
    }
}
