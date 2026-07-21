export default function About() {
  return (
    <>
      <h1>About DroneComNet</h1>
      <p className="lead">
        When a disaster knocks out the cellular network, rescue teams lose the
        one thing they need most: a way to find people and coordinate. Our
        drone-mounted modules rebuild a local network on the spot.
      </p>
      <h3>How it works</h3>
      <ul className="prose">
        <li>
          Each module is a Raspberry Pi with two radios: a 5 GHz access point
          victims and rescuers connect to, and a 2.4 GHz ad-hoc link that
          forms a delay-tolerant mesh between drones.
        </li>
        <li>
          Messages sync between drones whenever they are in range, so a report
          filed at one drone reaches the others and the ground control centre
          even without an always-on link.
        </li>
        <li>
          A LoRa fallback beacon keeps a drone locatable even if its main
          computer fails.
        </li>
        <li>
          The AeroSync system drone adds a flight controller the ground control
          centre can command directly.
        </li>
      </ul>
      <p className="muted">
        This site is part of a final-year engineering project. Products and
        specifications are a working prototype, not a commercial offering.
      </p>
    </>
  );
}
