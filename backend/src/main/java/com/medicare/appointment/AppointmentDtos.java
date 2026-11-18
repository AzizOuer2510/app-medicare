package com.medicare.appointment;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDateTime;
import java.util.List;

public final class AppointmentDtos {

    private AppointmentDtos() {}

    public record AppointmentRequest(
            @NotNull LocalDateTime dateTime,
            Long doctorId,
            @NotBlank @Size(max = 120) String doctorName,
            @Size(max = 500) String reason,
            @Size(max = 80) String appointmentType,
            AppointmentStatus status) {}

    public record PersonSummary(Long id, String fullName, String email) {
        public static PersonSummary from(com.medicare.user.entity.User user) {
            return user == null ? null : new PersonSummary(user.getId(), user.getFullName(), user.getEmail());
        }
    }

    public record AppointmentResponse(
            Long id,
            PersonSummary user,
            LocalDateTime dateTime,
            Long doctorId,
            String doctorName,
            String reason,
            String appointmentType,
            AppointmentStatus status) {

        public static AppointmentResponse from(Appointment appointment) {
            return new AppointmentResponse(
                    appointment.getId(),
                    PersonSummary.from(appointment.getUser()),
                    appointment.getDateTime(),
                    appointment.getDoctor() == null ? null : appointment.getDoctor().getId(),
                    appointment.getDoctorName(),
                    appointment.getReason(),
                    appointment.getAppointmentType(),
                    appointment.getStatus());
        }
    }

    public record SecretaryAppointmentRequest(
            @NotNull Long patientId,
            @NotNull LocalDateTime dateTime,
            @NotNull Long doctorId,
            @Size(max = 500) String reason,
            @Size(max = 80) String appointmentType,
            AppointmentStatus status) {}

    public record SecretaryAppointmentResponse(
            Long id,
            Long patientId,
            String patientName,
            String patientEmail,
            LocalDateTime dateTime,
            Long doctorId,
            String doctorName,
            String reason,
            String appointmentType,
            AppointmentStatus status,
            LocalDateTime reminderSentAt) {

        public static SecretaryAppointmentResponse from(Appointment appointment) {
            var patient = appointment.getUser();
            return new SecretaryAppointmentResponse(
                    appointment.getId(),
                    patient.getId(),
                    patient.getFullName(),
                    patient.getEmail(),
                    appointment.getDateTime(),
                    appointment.getDoctor() == null ? null : appointment.getDoctor().getId(),
                    appointment.getDoctorName(),
                    appointment.getReason(),
                    appointment.getAppointmentType(),
                    appointment.getStatus(),
                    appointment.getReminderSentAt());
        }
    }

    public record PatientSummary(Long id, String fullName, String email) {}

    public record SecretaryProfile(boolean secretary, boolean admin, List<PersonSummary> doctors) {}

    public record AssignmentRequest(
            @NotBlank @Size(max = 160) String secretaryEmail,
            @NotNull Long doctorId) {}

    public record AssignmentResponse(Long id, PersonSummary secretary, PersonSummary doctor) {
        public static AssignmentResponse from(SecretaryDoctorAssignment assignment) {
            return new AssignmentResponse(
                    assignment.getId(),
                    PersonSummary.from(assignment.getSecretary()),
                    PersonSummary.from(assignment.getDoctor()));
        }
    }

    public record AppointmentStatistics(
            long total,
            long upcoming,
            long confirmed,
            long completed,
            long cancelled) {}

    public record NoShowRisk(
            Long appointmentId,
            int score,
            String level,
            List<String> factors) {}
}
