class SendAlertsJob < ApplicationJob
  queue_as :alerts

  ALERTER_FUNCTION = 'alerter'

  MODES = {
    send_recall_alerts: { sendRecallAlerts: true },
    send_vehicle_recall_alerts: { sendVehicleRecallAlerts: true },
    review_vins: { reviewVins: true, sendVehicleRecallAlerts: true }
  }

  def perform(mode)
    AwsHelper.invoke(ALERTER_FUNCTION, MODES[mode.to_sym])
  rescue StandardError => e
    logger.warn "Failed to launch Alerter -- #{e}"
  end

end
