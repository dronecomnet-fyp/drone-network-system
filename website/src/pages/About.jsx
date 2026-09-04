export default function About() {
  return (
    <div className="about-page">
      <div className="section-header">
        <div className="section-subtitle">PROJECT BACKGROUND & ARCHITECTURE</div>
        <h1 className="section-title">About Aero-Link</h1>
        <p className="section-lead">
          When catastrophic disasters sever cellular backhauls and power grids, search and rescue
          teams lose the critical asset they need most: a way to locate victims and coordinate
          field response. Aero-Link airborne communication nodes deploy in minutes to re-establish
          a resilient local network directly over the disaster sector.
        </p>
      </div>

      <div className="about-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '20px', margin: '30px 0' }}>
        <div className="workflow-step">
          <div className="step-number" style={{ color: 'var(--cyan)' }}>01</div>
          <h3 className="step-title">Dual-Band Radio Architecture</h3>
          <p className="step-text">
            Each payload combines a high-power 5 GHz 802.11a/n access point for zero-install civilian
            and rescuer smartphones with an independent 2.4 GHz 802.11s ad-hoc mesh interface
            dedicated to peer-to-peer inter-drone communication.
          </p>
        </div>

        <div className="workflow-step">
          <div className="step-number" style={{ color: 'var(--cyan)' }}>02</div>
          <h3 className="step-title">Delay-Tolerant Store-and-Forward</h3>
          <p className="step-text">
            Swarm nodes synchronize emergency distress reports, voice messages, and casualty
            locations whenever drones fly within mutual communication range (up to 900m),
            ensuring messages propagate back to base even across fragmented topologies.
          </p>
        </div>

        <div className="workflow-step">
          <div className="step-number" style={{ color: 'var(--cyan)' }}>03</div>
          <h3 className="step-title">LoRa Fallback Telemetry</h3>
          <p className="step-text">
            An ultra-low-power independent LoRa transceiver beacon broadcasts GPS coordinates
            and critical battery metrics up to 3,000m, keeping every node locatable even in the
            event of a primary flight computer or battery fault.
          </p>
        </div>

        <div className="workflow-step">
          <div className="step-number" style={{ color: 'var(--cyan)' }}>04</div>
          <h3 className="step-title">Autonomous Swarm Integration</h3>
          <p className="step-text">
            The AeroSync 5 system drone integrates a CC3D flight controller that the Ground Control
            Centre (GCC) commands over MAVLink, allowing dynamic airborne repositioning to bridge
            coverage dead-zones in real time.
          </p>
        </div>
      </div>

      <div className="lookup-card" style={{ marginTop: '40px' }}>
        <div className="lookup-text">
          <h3>Academic Final Year Engineering Project</h3>
          <p>
            This website and its associated hardware specifications represent an active Final Year Project (FYP)
            research prototype developed for humanitarian disaster relief and emergency mesh communications.
          </p>
        </div>
      </div>
    </div>
  );
}
