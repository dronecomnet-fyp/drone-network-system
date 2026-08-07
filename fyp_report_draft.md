**Content**
===========

1 Introduction

1.1 Background

1.2 Problem Statement

1.3 Objectives and Scope

1.4 Report Structure

2 Literature Review

3 **System Architecture**

3.1 Overall System Design

3.2 Three-Layer Architecture (GCS / Drone Network / User Access)

3.3 Dual-Unit Node Architecture (RPi + ESP32-C3)

3.4 Design Evolution - Proper Plan vs Implemented Version

(adapted from your Gap Analysis document)

4 **Hardware Design**

4.1 Component Selection and Justification

4.2 Power System Design

4.3 Main Compute Unit

4.4 Auxiliary Module

4.5 Enclosure Design

4.6 Mounting System

5 Software Design

5.1 Wi-Fi Access and Captive Portal

5.2 DTN Sync Engine

5.3 API Server

5.4 Database Design

5.5 BLE / GPS / LoRa Integration

5.6 Time Synchronization Architecture

5.7 Fallback Mode Logic

5.8 Security Layer (RSP protocol)

5.9 Flutter Rescue App / Ground Station Dashboard

6 Testing and Results

6.1 Unit Testing

6.2 Integration Testing

6.3 Field Testing (once done)

6.4 Battery Runtime Verification

7 Discussion

7.1 Gap Analysis Outcome

7.2 Limitations

7.3 Cost Analysis

**Chapter 2: Literature Review**
================================

**2.1 Delay Tolerant Routing for Post-Disaster UAV Networks**
-------------------------------------------------------------

Arafat and Moh [[\[1\]]{.underline}](#references-for-new-literature-review-chapter) propose a location aided delay tolerant routing (LADTR) protocol specifically designed for UAV networks operating in post disaster scenarios. In these environments, unstable links and intermittent connectivity make conventional packet forwarding unreliable. The authors note that search and rescue operations after natural disasters depend on wireless communication provided by UAVs, which can capture and relay data despite unstable links and intermittent connectivity in highly dynamic networks. Their protocol combines location aided forwarding with a store carry-forward technique. It also introduces the concept of ferrying UAVs specifically to enable this store carry forward mechanism. The authors present this as the first attempt at using dedicated ferrying nodes for UAV network routing.

This work is directly relevant to the DTN synchronization mechanism described in Section 3.3.5 and Section 5.2 of this report. The store carry forward principle that LADTR formalizes for UAV networks is the same underlying principle applied in this project\'s presence beacon and pull synchronization design. A node holds data until an opportunity to forward it becomes available, rather than assuming a continuously available end to end path. Where LADTR relies on location information to decide which node is best positioned to carry a message forward, this project\'s implementation takes a simpler approach suitable for its fixed three node fleet. Data is replicated to every reachable peer rather than making a location informed forwarding decision. This is a reasonable simplification given the small, known node count in this system. However, it means that the more sophisticated forwarding decision logic introduced by LADTR would become relevant if the network were expanded to a larger number of nodes, as discussed in the future work presented in Chapter 9.

**2.2 Multi-UAV Networks for Disaster Monitoring**
--------------------------------------------------

Chandran and Vipin [[\[2\]]{.underline}](#references-for-new-literature-review-chapter) provide a broad review of multi UAV networks used in disaster scenarios. They examine the role of UAVs as communication relays in areas where ground infrastructure has been compromised. The authors note that UAVs establish temporary networks that support coordination among emergency responders and enable timely assistance to survivors. They also highlight that deployment strategies, data processing, routing, and security remain open research challenges that require further work to improve ad hoc networking solutions. The review concludes that ad hoc networking solutions for disaster response UAV fleets are still immature, particularly in the areas of deployment strategy, routing, and security. These three areas form the main focus of this project\'s design work.

This survey identifies security as an underdeveloped area in multi UAV disaster networks. This directly motivated the security architecture presented in Section 5.8 of this report. A purpose built threat model, role based authentication, and cryptographic key separation were developed because existing multi UAV disaster communication research, as this review confirms, has focused more on routing and coverage than on security. Similarly, the review\'s emphasis on deployment strategy as an open problem is reflected in this project\'s explicit distinction between volunteer operated and system owned nodes described in Section 3.1. This distinction is intended to address the practical deployment challenge of supplementing a fixed fleet of project owned drones with externally contributed hardware during a real disaster response.

**2.3 Security in Drone Communication Networks**
------------------------------------------------

Hassija et al. [[\[3\]]{.underline}](#references-for-new-literature-review-chapter) present a comprehensive survey of security, reliability, and communication requirements specific to drone networks. The survey examines authentication, encryption, and threat mitigation techniques suitable for the unique constraints of UAV platforms. These constraints include limited computational capacity, intermittent connectivity, and the physical exposure of drone hardware to capture or tampering. The survey also systematically catalogues the security threats faced by drone communication systems and the corresponding mitigation techniques. These include cryptographic authentication schemes, physical layer security techniques, and network level defences against jamming and spoofing.

This survey\'s discussion of drone specific security challenges, particularly its emphasis on the physical exposure of drone hardware as a distinct threat category, is directly reflected in the physical capture threat category addressed in Section 5.8.8 of this report. Conventional network security literature does not typically treat this as a major concern. In this project, the consequences of a node falling into an adversary\'s physical possession are treated as a residual risk that requires a procedural response rather than a purely cryptographic one.

More broadly, the survey\'s emphasis on authentication schemes suitable for resource constrained, intermittently connected drone platforms supports this project\'s adoption of a decentralized, offline verifiable PIN based credential system, described in Section 3.2.4 and Section 5.8.5. This approach is preferred over a conventional centralized authentication server, which would reintroduce the single point of failure that a drone based disaster communication network is specifically designed to avoid.

**Chapter 3: System Architecture**
==================================

**3.1 Overall System Design**
-----------------------------

The system is designed as a fully decentralized, infrastructure independent communication network intended for deployment during disaster response operations. The main objective of this architecture is to enable communication between affected individuals and rescue teams in situations where cellular networks, internet connectivity, and fixed communication infrastructure are unavailable or have been damaged.

The system consists of three drone mounted communication nodes that operate collaboratively without depending on a central server or backend system. Two of these nodes, named DRONE\_A and DRONE\_B, are operated using volunteer drones. Each node contains an identical communication module with the same hardware and software configuration. The third node, DRONE\_S, is mounted on a system owned drone. It runs the same node software as DRONE\_A and DRONE\_B without modification. In addition, DRONE\_S hosts a MAVLink gateway service that provides a communication path between the Ground Control Center and the system drone\'s flight controller for control and telemetry purposes. Unlike DRONE\_A and DRONE\_B, DRONE\_S does not include an Auxiliary Module. This is because only two Auxiliary Module hardware units are available, and both are allocated to the volunteer operated nodes. As a result, DRONE\_S does not provide its own GPS derived time source or LoRa fallback beacon capability. Instead, it relies on relative timestamps as described in Section 3.3.3. A future enhancement could provide MAVLink based GPS time synchronization for DRONE\_S, as noted in the design record for this node.

This difference between volunteer operated and system owned nodes supports the project\'s goal of handling a heterogeneous drone fleet. Volunteer drones can join the network as equal peers for message relay operations, while the system owned drone provides additional functionality by connecting the mesh network with the Ground Control Center. Where flight controller integration is available, it can also provide direct drone control capabilities.

The complete system is implemented across four software repositories:

-   drone-network-system - The primary repository for the current implementation of the system. It contains the backend running on each drone node\'s Raspberry Pi, including the FastAPI application server, HTTP captive portal service, database layer, always-on synchronization daemon, Auxiliary Module communication bridge, audit logging, and rate limiting. It also includes the system deployment tools, node configuration templates, systemd service definitions, the ESP32-C3 Auxiliary Module firmware, the Ground Control Center desktop application, and the public facing Emergency Application described in Section 3.2.5.

-   rescue-personnel-app - the mobile application used by rescue team members operating in the field.

-   local-server -The Phase 1 implementation of the per node backend. It is retained for reference but has been replaced by the backend now included in drone-network-system. Its role in the project\'s evolution is discussed in Section 3.4.

-   ground-center-app - An early prototype of the Ground Control Center built using the Tauri framework. It has been replaced by the Flutter based desktop application now included in drone-network-system. The reason for this change is discussed in Section 3.4.

The deployment scripts associated with local-server and the Windows packaging process for the Ground Control Center are considered part of the same overall system delivery. Shared data models are used across the Ground Control Center, rescue personnel application, and Emergency Application to maintain consistent API communication.

The architecture is built around three main design principles established at the beginning of the project and validated throughout implementation.

The first principle is full decentralization. The communication mesh does not depend on a central server, fixed access point, or single coordination point. Every node, whether volunteer operated or system owned, is capable of accepting user requests, storing message data, and providing rescue team interfaces. This principle directly addresses the main problem targeted by the project. During disaster situations, existing communication infrastructure cannot be assumed to remain available. Therefore, a system depending on centralized infrastructure would be vulnerable to the same failures it is designed to overcome.

The second principle is opportunistic, delay tolerant communication between nodes, implemented through an always on ad-hoc wireless mesh network instead of a continuously connected network. Since drone nodes are mobile, they may sometimes be separated by distances beyond direct wireless communication range. Therefore, the system does not assume that all three nodes are reachable at the same time. Instead, all nodes remain members of the same ad-hoc wireless network, and a periodic synchronization process identifies currently available peers and exchanges any pending data between them. Each synchronized record is cryptographically signed, as described in the security architecture in Chapter 5, ensuring that transmitted data cannot be forged or modified during communication between nodes.

This mechanism allows the network to achieve eventual consistency. This means that when nodes have sufficient opportunities to communicate, all nodes will eventually contain the same set of data, even though continuous connectivity between all nodes is not guaranteed. The detailed operation of this synchronization mechanism is explained in Section 3.3.

The third principle is the fault tolerant dual unit node design, which applies to DRONE\_A and DRONE\_B. Each of these nodes consists of two independently powered sub units: a Main Compute Unit, based on a Raspberry Pi 4 Model B, and an Auxiliary Module, based on a Seeed Studio XIAO ESP32-C3 microcontroller. This separation ensures that the system can continue providing important information even if the main computing unit fails.

If the Main Compute Unit becomes unavailable, the Auxiliary Module can continue operating independently and transmit the node\'s last known GPS location, battery status information, and most recently received message through a long range LoRa communication channel. This fallback behaviour was designed based on the practical reality that drone hardware operating in disaster environments has a higher risk of partial failure compared to fixed communication infrastructure. Even incomplete information from a partially failed node can provide valuable support for rescue coordination.

### **3.1.1 Functional Overview**

At a functional level, the system supports the following core capabilities. Each capability is described in detail in the corresponding sections of this chapter, as well as in Chapter 4 (Hardware Design) and Chapter 5 (Software Design):

-   Acceptance of help requests from affected individuals without requiring any prior software installation, through a captive portal interface served directly by each node.

-   A dedicated Emergency Application for members of the public, providing background location logging and BLE triggered notifications about nearby drone availability, as described in Section 3.2.5.

-   Local storage of all messages and related records using an embedded SQLite database on each node.

-   Propagation of messages, personnel records, announcements, field reports, and check in data between nodes using a signed, always on synchronization mechanism operating over a dedicated ad-hoc wireless mesh.

-   Discovery of the drone network by nearby users through Bluetooth Low Energy (BLE) advertisement broadcasts from the Auxiliary Module, where available.

-   Long range transmission of critical message summaries and status data using a LoRa radio module, extending situational awareness beyond the effective range of the primary Wi-Fi network.

-   GPS based positioning and time synchronization, allowing equipped nodes to accurately timestamp messages and report their physical location without relying on internet based time servers or manual configuration.

-   Continuous monitoring of onboard battery systems, allowing the ground station to track the operational health of all deployed nodes in real time.

-   A degraded fallback mode of operation, where an Auxiliary Module independently transmits essential health and location data even after the failure of its node\'s Main Compute Unit.

-   Decentralized and offline verifiable authentication of rescue personnel using a PIN-based credential system, described in Section 3.2.4.

-   A dedicated mobile application for rescue team personnel to view, claim, and manage incoming requests, as well as to compose and receive announcements.

-   A Ground Control Center desktop application for the ground station operator to monitor the overall network status, manage personnel credentials, plan operations using an offline map, and, for the system owned drone, monitor and control the aircraft when appropriate.

### **3.1.2 High Level System View**

At the highest level, the system can be understood as three cooperating layers. Together, these layers support four categories of participants in a disaster response operation: members of the public who may require assistance, affected individuals actively submitting requests, rescue teams, and command-level coordinators. The User Access Layer serves the first two participant categories. Both interact with the same drone node, either through the captive portal or the Emergency Application.

![](media/image1.png){width="4.203125546806649in" height="5.180596019247594in"}

Figure 3.1: Three Layer System Architecture

The User Access Layer consists of the interaction points between the public and the nearest available drone node. This layer supports two different methods of accessing the system, both using the same underlying message and check in storage system. A user without the Emergency Application installed can still submit a request directly through the node\'s captive portal, as described in Section 3.2.1. A user with the application installed can benefit from additional features, including passive background monitoring and more complete data uploads, as described in Section 3.2.5.

The Drone Network Layer consists of the three physical drone nodes and the ad-hoc wireless mesh connecting them, as described in Section 3.2.2. Each node independently receives, stores, and forwards data using the synchronization mechanism described in Section 3.3. This communication operates over a dedicated 2.4 GHz ad-hoc backbone, which is physically and logically separated from the 5 GHz access point used for user connectivity, as detailed in Section 3.2.3.

The Ground Control and Rescue Layer consists of the interfaces used by rescue team members and the ground station operator to interact with the network. Rescue personnel authenticate using the PIN based credential system described in Section 3.2.4 and use a dedicated mobile application to view and claim requests. A ground station operator uses the Ground Control Center desktop application, described in Section 3.2.4, to connect to any available node within communication range. Additionally, DRONE\_S provides an extra communication path for flight telemetry and control, either through a direct connection or through the mesh network.

**3.2 Three Layer Architecture**
--------------------------------

Building on the overview presented in Section 3.1, this section describes each architectural layer in greater detail. It covers the operation of the ad-hoc mesh backbone, the dual radio communication design, the personnel authentication mechanism, and the Emergency Application. Together, these components provide the functionality required for communication, coordination, and data exchange within the system.

### **3.2.1 User Access Layer**

The User Access Layer represents the point of first contact between an affected individual and the drone communication network. This layer is intentionally designed to require no prior technical knowledge, no software installation, and no advance preparation. This reflects the reality that individuals in a disaster situation may be under significant physical and psychological stress.

Discovery of the network begins passively. Where an Auxiliary Module is present, it continuously broadcasts a Bluetooth Low Energy (BLE) advertisement containing the node\'s Wi-Fi network identifier and node identity. A user\'s smartphone can detect this advertisement using the standard Bluetooth scanning functionality provided by the operating system, without requiring any dedicated application.

Once the user connects to the node\'s 5 GHz Wi-Fi access point, an HTTP captive portal is automatically displayed, following the same detection mechanism commonly used by public Wi-Fi networks. In the current implementation, the captive portal and the message submission form are combined into a single page served entirely over HTTP on port 80. This is a deliberate Phase 2 design decision rather than an oversight. An earlier version of the system redirected users to a separate self signed HTTPS submission page. However, this approach created two practical issues. First, users were presented with certificate warnings that many found difficult to bypass, particularly on mobile devices. Second, some platforms showed inconsistent captive portal detection behaviour when the initial page was served over HTTPS. Since the self signed certificate does not provide meaningful authentication to an anonymous victim, the security benefit of HTTPS on this specific page was considered limited. The usability issues introduced by HTTPS were therefore judged to outweigh its advantages. As a result, the entire victim facing workflow was consolidated onto HTTP. This decision and its associated security trade offs are examined in detail in the security architecture presented in Chapter 5.

Message integrity on this open and unencrypted communication path is protected at the point of ingestion. Every submitted message is cryptographically signed by the receiving node\'s backend before being stored. This ensures that once a message has been accepted by the system, it cannot be modified without detection. By design, confidentiality during transmission is given lower priority than integrity and availability on this particular communication path. The reasoning behind this prioritization is also discussed in Chapter 5.

Through the submission form, the user can provide a free text description of their situation, an optional GPS location obtained through the browser, and an optional written landmark description. A persistent, randomly generated device identifier is stored within the browser and displayed to the user as a short reference code. This code allows rescue personnel to verify the user\'s identity when contact is established. No account creation, registration, or authentication is required. This design choice is consistent with the goal of minimizing barriers between the user and the ability to request assistance.

A user who has already installed the Emergency Application, described in Section 3.2.5, does not need to interact with the captive portal directly. Instead, the application automatically performs an equivalent submission through a dedicated check in endpoint when the device connects to the node\'s Wi-Fi network.

![](media/image2.png){width="2.7986614173228346in" height="4.496379046369204in"}

Figure 3.2: Captive portal flow, showing User connects to Wi-Fi → HTTP captive portal auto-opens (instructions only) → user redirected → HTTPS submission page opens → message submitted over TLS

### **3.2.2 Drone Network Layer**

The Drone Network Layer forms the operational core of the system and is responsible for receiving, storing, and propagating data across the three deployed nodes.

Rather than establishing connections between nodes only when needed, all three nodes maintain permanent membership in a single ad-hoc (IBSS) wireless cell operating on a dedicated 2.4 GHz radio. Each node uses a fixed, statically assigned address within this network. This ad-hoc cell functions as a shared, always-on wireless segment. Whenever two nodes are within communication range of each other, they can exchange data directly. Unlike a conventional Wi-Fi network, no connection establishment or teardown process is required before communication can occur.

Instead of one node actively initiating communication with another, each node periodically broadcasts a short, cryptographically signed presence beacon across the shared wireless cell. This beacon announces the node\'s identity and provides a summary of the record counts currently stored in each replicated data table. Every node maintains a continuously updated view of nearby peers based on these beacons. A peer is considered reachable only while its beacons continue to arrive within the expected time interval. At regular intervals, each node attempts to retrieve outstanding data from every peer that is currently considered reachable. Only records that are not already stored locally are requested. This synchronization process applies to all replicated data types, including victim messages, personnel credentials, announcements, field reports submitted by rescue teams, and check in data generated by the Emergency Application. Every record exchanged during synchronization is individually signed and independently verified by the receiving node before being accepted. This ensures that data cannot be forged or modified by an intermediary, even though the underlying wireless cell itself does not use link layer encryption.

This shared, always on cell design was adopted because it removes the timing related issues that can occur in systems where nodes must take turns connecting to one another. In such systems, two nodes may fail to synchronize simply because both happen to be in the wrong operating mode at the same time. This problem existed in an earlier design iteration and is discussed further in Section 3.4. Because message data does not need to be delivered across the network in real time, and because different nodes may temporarily hold different subsets of the overall record set, the network operates using eventual consistency rather than instantaneous consistency. This means that, given sufficient opportunities for any two nodes to be within communication range at the same time, all synchronized data will eventually converge and become identical across the entire fleet.

![](media/image3.png){width="4.536458880139983in" height="3.8883923884514435in"}

Figure 3.3: Drone Network Layer internal view

### **3.2.3 Wi-Fi Dual-Radio Separation**

A central architectural decision in the **Drone Network Layer** is the physical separation of user-facing connectivity from inter node mesh traffic. This is achieved by assigning each function to a dedicated wireless radio operating on a different frequency band.

The onboard Wi-Fi radio of the **Raspberry Pi 4 Model B** is used exclusively as a **5 GHz Access Point** for affected individuals and rescue team personnel. This radio remains in access point mode throughout normal operation and is never reconfigured for any other purpose. The use of the **5 GHz band**, instead of the more common **2.4 GHz band**, is a deliberate design choice. It keeps user traffic separate from the mesh backbone traffic described below. A limitation of this approach, discussed in **Chapter 8**, is that devices supporting only 2.4 GHz Wi-Fi cannot connect to the user facing access point.

A second wireless radio, implemented using a **USB connected Atheros AR9271 802.11n adapter**, is dedicated exclusively to the ad-hoc mesh backbone described in **Section 3.2.2**. This radio operates continuously on a fixed **2.4 GHz channel**. Unlike the earlier single radio prototype discussed in **Section 3.4**, this radio is not reconfigured between different operating modes. It remains permanently connected to the ad hoc wireless cell for the entire duration of node operation.

![](media/image4.png){width="5.432292213473316in" height="3.690709755030621in"}

Figure 3.4: Dual-radio separation diagram for a single node

This separation removes a stability issue that existed in an earlier single radio prototype. In that design, a single radio had to alternate between acting as an access point and connecting to peer nodes for synchronization. Each synchronization attempt temporarily interrupted the access point, causing connected users to lose their connection for a short period. By introducing a dedicated second radio that remains permanently connected to the mesh network, the user facing access point can continue operating without interruption. The transition from the earlier single radio design to the current architecture is discussed further in **Section 3.4**.

### **3.2.4 Ground Control and Rescue Layer**

The Ground Control and Rescue Layer encompasses the interfaces through which rescue team members and a ground station operator interact with the network, together with the authentication mechanism that controls access to these interfaces. Personnel authentication is designed to avoid the use of a single, shared access credential for all rescue team members. Instead, the system implements an individual and decentralized authentication scheme.

A ground station operator creates a credential for a specific individual through the Ground Control Center. During this process, the system generates a one time plaintext PIN, which is displayed only once during credential creation and is never stored in plaintext. After generation, only a salted cryptographic hash of the PIN is stored. To authenticate, a rescue team member provides their assigned identifier and PIN to any connected drone node. The node verifies the submitted details against its own DTN synchronized copy of the personnel records. If authentication is successful, the node generates a compact, cryptographically signed, time limited session token. Since this token is signed using a secret shared across the drone fleet, any node can independently verify the token\'s validity, not only the node that originally issued it. This follows the decentralization principle established in Section 3.1. If a credential needs to be revoked, the updated credential status is propagated across the fleet through the same synchronization mechanism described in Section 3.2.2. As a result, revocation becomes effective across all nodes after the next successful synchronization cycle with each node. This delay is considered a known and accepted property of the design rather than a system failure.

Rescue team personnel authenticate using the credential system described above and use a dedicated mobile application to interact with the network. The application allows rescue personnel to view all messages available on the connected drone node, claim requests for follow up actions, submit field reports to headquarters, and receive announcements from the Ground Control Center. When a rescue request is claimed, the updated status is propagated across the fleet using the same synchronization mechanism used for message data.

The ground station operator uses the Ground Control Center, a desktop application developed using the Flutter framework and deployed on the Windows platform. The application connects to any drone node currently within Wi-Fi range and uses the same personnel authentication system described above. Since the application\'s view of the overall network depends on the latest successful synchronization cycle, the displayed data may not always represent the current real-time state of the entire fleet. Therefore, each dataset shown in the application includes an indication of its age rather than being presented as live information. The application provides several operational features, including an offline map interface using pre downloaded map tiles, since internet connectivity cannot be assumed during disaster operations. The map supports overlays for drone node locations, victim messages, Emergency Application check-in data, and rescue team field reports. It also provides a planning mode where operators can place advisory markers and coverage indicators during deployment preparation.

Additional features include a consolidated victim message feed, node health monitoring based on telemetry described in Section 3.3, personnel credential management, and an announcement creation interface. For the system owned node DRONE\_S, the application additionally provides a flight telemetry interface and, where appropriate safety conditions are satisfied, a drone control interface. This functionality communicates with the onboard MAVLink gateway either directly when the operator\'s laptop is connected to DRONE\_S\'s access point, or through the ad-hoc mesh backbone described in Section 3.2.2 when the operator is connected through DRONE\_A or DRONE\_B. The drone control functionality, its staged implementation approach, and its safety limitations are discussed in the hardware and software integration details for DRONE\_S in Chapter 4 and Chapter 5. Its security considerations are addressed separately in the security architecture presented in Chapter 5.

### **3.2.5 Emergency Application**

In addition to the captive portal described in Section 3.2.1, the system provides a dedicated mobile application for members of the public. This application is separate from the rescue personnel application and is intended to be installed before a disaster occurs. The application performs two main functions without requiring an active connection to a drone node. First, it periodically records the user\'s device location in the background at a low frequency and stores this location history locally on the device. Second, it can scan for the Bluetooth Low Energy (BLE) advertisement broadcast by a node\'s Auxiliary Module, as described in Section 3.2.1, after the user has explicitly enabled this function through the application interface. This scanning process does not require the user to manually connect to any network. However, the user must first activate the scanning feature. The reasons for this requirement are explained in Section 5.7.2.

Both Android and iOS restrict background applications from automatically opening themselves when a passive scan result is detected. Android also restricts continuous, unfiltered background scanning unless the application is running as a foreground service with a persistent notification. Because of these platform limitations, the application requires the user to explicitly enable a watch mode before background scanning begins. It does not start scanning automatically and continuously after installation. The application also cannot directly open itself when a nearby drone node is detected while it is running in the background. Instead, when a valid drone advertisement is detected, the application generates a high priority system notification informing the user that a rescue drone has been detected nearby. When the user selects this notification, the application assists the user in connecting to the corresponding node\'s Wi-Fi access point. After the connection is established, the application automatically uploads the previously stored location history together with an optional urgent SOS indication to the drone node. This data is submitted through a dedicated check in submission endpoint, which is separate from the standard message submission endpoint used by the captive portal. If the user indicates an SOS request, the check in process also creates a standard rescue message. This ensures that the request enters the same rescue team workflow as other rescue requests, regardless of which submission method was used.

**3.3 Dual Unit Node Architecture**
-----------------------------------

This section describes two related but separate mechanisms that operate within the drone network. The first mechanism is the internal relationship between each node\'s Main Compute Unit and Auxiliary Module, which was introduced in Section 3.1 and is described in detail in Sections 3.3.1 to 3.3.4. The second mechanism is the process used to synchronize data between different drone nodes through the ad-hoc mesh backbone described in Section 3.2.2. This inter-node synchronization mechanism is discussed in detail in Section 3.3.5.

![](media/image5.png){width="4.345165135608049in" height="3.9481813210848644in"}

Figure 3.5: Dual-unit node block diagram

### **3.3.1 Main Compute Unit and Auxiliary Module Roles**

The Main Compute Unit, built around a Raspberry Pi 4 Model B, is responsible for most of a node\'s communication and application functions during normal operation. It hosts the Wi-Fi access point used by users, runs the captive portal service described in Section 3.2.1, manages the local SQLite database, participates in the synchronization mechanism described in Section 3.3.5 through the dedicated mesh radio, and provides the authenticated APIs used by the rescue personnel mobile application and the Ground Control Center.

The Auxiliary Module, built around a Seeed Studio XIAO ESP32-C3 microcontroller, handles a smaller set of specific functions. These include collecting GPS location and time data, monitoring both onboard battery packs, and broadcasting the node\'s BLE discovery advertisement. This module is available only on DRONE\_A and DRONE\_B. As mentioned in Section 3.1, DRONE\_S does not include an Auxiliary Module because only two such hardware sets are available. Therefore, functions normally provided by the Auxiliary Module are not available on DRONE\_S. It does not have an independent GPS time source and uses relative timestamping as described in Section 3.3.3. It also does not support the fallback beacon capability described in Section 3.3.4, since this functionality depends on the Auxiliary Module.

### **3.3.2 Inter Unit Communication Link**

Where an Auxiliary Module is available, the two sub units communicate through a wired USB serial connection. The XIAO ESP32-C3\'s USB-C interface is connected to a USB-A port on the Raspberry Pi. On the Raspberry Pi side, this connection appears as a standard serial device and is managed by a dedicated software component responsible for communication between the two sub-units.

Data exchanged through this link is structured as newline delimited JSON messages. During normal operation, the Main Compute Unit sends a lightweight heartbeat signal to the Auxiliary Module at a fixed short interval. The Auxiliary Module monitors this heartbeat and considers a continuous absence of the signal as an indication that the Main Compute Unit has failed. This behaviour forms the basis of the mode switching mechanism described in Sections 3.3.3 and 3.3.4. In addition to the heartbeat, the Auxiliary Module periodically sends GPS and battery telemetry to the Main Compute Unit. The Main Compute Unit can also send commands to the Auxiliary Module, such as requesting a LoRa summary packet transmission and forwarding newly received messages so they can be stored for possible fallback operation. The detailed message types and data formats used in this communication link are described in Chapter 5.

### **3.3.3 Normal Operation Mode**

![](media/image6.png){width="5.098958880139983in" height="4.607696850393701in"}

Figure 3.6: Normal operation mode data flow

While the Main Compute Unit is operating normally, the Auxiliary Module works only as a sensor and data provider. It does not make independent decisions about what data should be transmitted or when it should be transmitted. The Auxiliary Module continuously collects GPS location data and, after obtaining a satellite fix, GPS derived UTC time. It forwards this information to the Main Compute Unit. It also continuously monitors both battery packs and sends the collected readings to the Main Compute Unit. The BLE discovery advertisement is broadcast independently and continuously, as this function does not require any coordination with the Main Compute Unit. LoRa transmission is fully controlled by the Main Compute Unit. The Auxiliary Module sends a LoRa summary packet only when it receives an explicit instruction from the Main Compute Unit, which decides what long range data should be transmitted and when. Whenever a new message is received and stored by the Main Compute Unit, the message content is immediately forwarded to the Auxiliary Module. The Auxiliary Module stores this message in its own persistent flash memory as the node\'s cached last message. This ensures that a local copy of the most recent message remains available even if the Main Compute Unit stops operating.

Where no Auxiliary Module is available, such as on DRONE\_S, messages are timestamped using the elapsed time since the Main Compute Unit\'s own boot. These timestamps are marked accordingly because no external GPS based time source is available on that node.

### **3.3.4 Fallback Operation Mode**

![](media/image7.png){width="5.355725065616798in" height="5.872210192475941in"}

Figure 3.7: Fallback mode trigger and behaviour

If the heartbeat signal from the Main Compute Unit is missing for a continuous period, the Auxiliary Module automatically switches to fallback mode without requiring any external command. In this mode, BLE advertising is stopped, and communication through the USB serial link is suspended because the Main Compute Unit is no longer available for communication. The Auxiliary Module then takes full responsibility for periodically transmitting a compact LoRa beacon. This beacon contains the node\'s current GPS location, UTC time, voltage and current readings of both battery packs, and the most recently cached message.

A nearby node with an operational Main Compute Unit can receive and relay this beacon to the rest of the network. This allows the ground station to identify the degraded status of the failed node, even though its primary communication functions are no longer available. As mentioned in Section 3.3.1, this fallback capability is available only on DRONE\_A and DRONE\_B.

### **3.3.5 Inter Node Synchronization Mechanism**

Building on the ad-hoc mesh backbone introduced in Section 3.2.2, this section describes the specific mechanism used by nodes to detect each other\'s presence and exchange data across the shared wireless cell.

**Presence detection -** Each node periodically broadcasts a short, signed presence beacon across the shared ad-hoc cell at an interval shorter than the pull sync cycle described below. This beacon contains the node\'s identity, API port, timestamp, and a summary of the record counts currently stored in each table participating in synchronization. Each node maintains a list of currently reachable peers. A peer is added to this list when its beacon is received and removed if no new beacon is received within an expiry period slightly longer than the beacon interval. This allows each node to maintain an updated view of nearby nodes without requiring a connection based handshake.

**Pull synchronization** - At a fixed longer interval, each node attempts to retrieve missing data from every peer currently listed as reachable. For each peer, the node requests records that it does not already have from all synchronized tables: victim messages, personnel credentials, announcements, rescue team field reports, and Emergency Application check-in data. Each received record is verified using its embedded cryptographic signature before being stored locally. Any record that fails verification is rejected, and the failure is recorded in the node\'s audit log, described further in Chapter 5.

**Conflict resolution** - Since multiple nodes may independently contain different versions of the same record, especially when a message claim status changes, predefined rules are used to resolve conflicts during synchronization. For victim messages, a claimed status always takes priority over a new status, regardless of which node contains the latest information. This ensures that a rescue claim made on one node cannot be overwritten by another node that has not yet received the update. A similar rule applies to personnel credentials, where a revoked credential always takes priority over an active credential. Announcements, field reports, and check in records are handled as append only data. Since these records do not have changing states like messages or credentials, synchronization simply ensures that all nodes eventually receive the complete set of records.

This combination of continuously detecting nearby nodes and periodically exchanging missing data allows the network to achieve the eventual consistency property introduced in Section 3.1. Each exchanged record is verified using cryptographic signatures to ensure that the received data is authentic and has not been modified. This means that when two nodes come within communication range, they can exchange any missing information and gradually reach the same data state. The network does not require all nodes to be connected at the same time; instead, data is distributed whenever communication opportunities become available.

**3.4 Design Evolution**
------------------------

The architecture presented in Sections 3.1 to 3.3 was not the system\'s original design. It is the result of a deliberate Phase 2 redesign carried out after the initial prototype had successfully validated the project\'s core concept. The prototype demonstrated that a set of drone mounted nodes could accept messages from affected users, store them locally, and propagate them between nodes without relying on any central infrastructure. This section describes how the system evolved into its current form. It also explains the major design changes that were made and the reasons behind them, providing a transparent account of the project\'s development.

#### **3.4.1 Phase 1: The Validated Prototype**

The initial prototype, referred to throughout this section as Phase 1, successfully demonstrated the project\'s core concepts using a simple hardware configuration. It consisted of three Raspberry Pi 4 nodes, each using only its onboard Wi-Fi radio. There was no external mesh adapter, Auxiliary Module, GPS, or LoRa hardware. Despite this simple design, Phase 1 successfully demonstrated the key features required at that stage of the project. These included a captive portal for receiving messages from affected users, a local SQLite database, a pull based synchronization mechanism for propagating messages between nodes with per message HMAC signing and status based conflict resolution, a rescue team message claim workflow, and a role based API that separated rescue team, headquarters, and inter node synchronization access.

The main limitation of Phase 1, and the primary reason for the redesign described in this section, was that a node could not reliably serve users while also synchronizing with other nodes. Since each node had only one Wi-Fi radio, it had to switch between operating as a user facing access point and connecting to another node for synchronization. Every time the radio switched to perform synchronization, all connected users were briefly disconnected.

**Chapter 4: Hardware Design**
==============================

**4.1 Component Selection and Justification**
---------------------------------------------

This chapter presents the physical hardware architecture of a single drone communication node. It builds on the conceptual dual unit design introduced in Section 3.3. DRONE\_A and DRONE\_B use an identical hardware configuration. Each node includes both the Main Compute Unit and the Auxiliary Module described in this chapter. DRONE\_S uses the same Main Compute Unit hardware. However, it does not include an Auxiliary Module because only two Auxiliary Module hardware sets were built, and both are allocated to the volunteer-operated nodes. DRONE\_S\'s additional responsibilities, along with the hardware implications of not having an Auxiliary Module, are discussed in Section 4.1.9. The following sections describe how these components are integrated within the Main Compute Unit (Section 4.2) and the Auxiliary Module (Section 4.3).

Four main criteria were considered consistently during all hardware selection decisions:

-   Functional suitability - The component must satisfy the specific technical requirement it is selected for. Components with unnecessary additional capabilities that increase cost or power consumption were avoided.

-   Power efficiency - Since the system operates as a battery-powered drone payload, as explained in Section 4.4, the current consumption of each component was evaluated based on its contribution to the overall system runtime.

-   Local availability and cost - Components were selected from suppliers with reliable availability in Sri Lanka whenever possible. This helps reduce procurement delays and overall system cost.

-   Integration compatibility - Components must interface easily with either the Raspberry Pi 4 Model B or the XIAO ESP32-C3 using standard and well documented communication interfaces such as UART, SPI, I2C, or USB. This avoids the need for custom driver development.

![](media/image8.png){width="5.293225065616798in" height="4.8160575240594925in"}

Figure 4.1: Complete hardware component map for one node

### **4.1.1 Main Compute Platform - Raspberry Pi 4 Model B**

The Raspberry Pi 4 Model B was selected as the main compute platform for each drone node. This decision was based on the requirement to run a complete Linux based software stack. The system needs to support multiple services running simultaneously, including a FastAPI web server, an SQLite database, a DTN synchronization engine, and an auxiliary module communication bridge. Lower power microcontroller platforms, such as the ESP32 family used in the Auxiliary Module, are not suitable for this role. They cannot run a general purpose operating system or support a Python based application server with this level of complexity.

The Raspberry Pi 4B, compared to earlier Raspberry Pi models, was selected due to several key features. It includes an onboard dual band Wi-Fi radio, which supports the 5 GHz access point functionality described in Section 3.2.4. It also provides Gigabit Ethernet and USB 3.0 interfaces, which offer sufficient capacity for connecting the USB based mesh radio and the auxiliary module serial communication link. Additionally, its improved processing performance compared to previous models is important for handling multiple tasks at the same time. These include HTTPS request processing, database operations, and DTN synchronization activities. This ensures that message handling can be performed without introducing unacceptable delays.

### **4.1.2 Inter-Node Mesh Radio - Atheros AR9271 USB Wi-Fi Adapter**

As explained in Section 3.2.4, the inter node DTN synchronization backbone requires a radio interface that is physically and logically separate from the Raspberry Pi\'s onboard access point radio. For this purpose, a USB Wi-Fi adapter based on the Atheros AR9271 chipset was selected.

The AR9271 was chosen over other available USB Wi-Fi chipsets because of its mature and reliable support within the Linux kernel through the ath9k\_htc driver. This driver support is important for long duration field operation, as it avoids dependence on proprietary or poorly supported drivers. The chipset supports 802.11n client mode operation on the 2.4 GHz band, which is required for the mesh backbone communication. Additionally, its relatively low power consumption, discussed in the power analysis in Chapter 4.2, makes it suitable for this application. This is important because the radio remains continuously active during node operation instead of being periodically switched on and off through duty cycling.

### **4.1.3 Auxiliary Microcontroller - Seeed Studio XIAO ESP32-C3**

The XIAO ESP32-C3 was selected as the controller for the Auxiliary Module fitted to DRONE\_A and DRONE\_B, described in Section 3.3.

This selection was based on three main requirements:

-   The need for built-in Bluetooth Low Energy (BLE) support for the BLE discovery function described in Section 3.2.1.

-   The availability of sufficient GPIO, UART, SPI, and I2C interfaces to connect with the GPS module, LoRa module, and battery monitoring sensor simultaneously.

-   A compact physical size that allows easy integration within the node enclosure together with the other Auxiliary Module components.

The ESP32-C3 variant was selected instead of the more commonly used ESP32 or ESP32-S3 variants due to its lower power consumption. It also provides an integrated USB-to-serial capability through its native USB-C port. This allows a direct physical connection to the Raspberry Pi\'s USB port, as described in Section 3.3.2, without requiring an additional USB-to-UART bridge chip.

### **4.1.4 GPS Module - GY-GPS6MV2 (u-blox NEO-6M)**

The GY-GPS6MV2 module, based on the u-blox NEO-6M GPS receiver, was selected to provide the node positioning and GPS derived time synchronization functions described in Section 3.3. This module was selected over other available GPS modules due to several practical advantages related to the project\'s deployment requirements.

The GY-GPS6MV2 breakout board includes an onboard backup battery and built in EEPROM. These features allow the module to retain almanac and ephemeris (two critical datasets used by Global Navigation Satellite Systems, like GPS, to calculate exact locations on Earth ) data between power cycles. As a result, the module can achieve faster satellite acquisition during later startups after an initial GPS fix has been obtained. The module uses an external U.FL-connected ceramic antenna. This allows the antenna to be positioned separately within the node enclosure, specifically at the dedicated GPS antenna location shown in the enclosure design in Section 4.5. This improves satellite visibility when the enclosure is mounted on the drone frame.

The module communicates through a standard TTL level serial interface with a default baud rate of 9600 bps. This interface connects directly to a UART peripheral on the XIAO ESP32-C3 without requiring additional level shifting circuitry, as both devices operate using 3.3V logic levels. The NEO-6M receiver\'s 50 channel engine and specified 27 second cold-start acquisition time were evaluated against the system requirements. The performance was considered sufficient because the primary use of GPS data in this project is coarse node location reporting and message timestamping, rather than high precision navigation.

### **4.1.5 Long-Range Radio - HopeRF RFM95 (915 MHz)**

The RFM95 LoRa transceiver module, operating at 915 MHz, was selected to provide the long range fallback and summary transmission capability described in Section 3.1.1 and further explained in Section 3.3.4. LoRa modulation was selected because it provides a significantly longer communication range compared to the two Wi-Fi radios used in the node. However, this extended range comes with lower data throughput. This trade off is acceptable because the LoRa module is only used for transmitting compact summary data and fallback beacon messages, rather than complete message content or high bandwidth data.

The RFM95 module was selected due to several important features. It provides an SPI interface, which allows direct integration with the available peripherals of the XIAO ESP32-C3. It also offers a high receiver sensitivity of -148 dBm in LoRa mode, which helps maximize the possible communication range between nodes. Additionally, the module supports adjustable transmit power up to +20 dBm. This allows the transmit power to be adjusted during field deployment to achieve a balance between communication range and current consumption. The impact of transmit power on the overall power budget is discussed in Section 4.4. The 915 MHz frequency variant was selected as the suitable regional version for the intended deployment. The regulatory status of this frequency band is identified as a verification item in the limitations discussed in Chapter 8.

### **4.1.6 Battery Monitoring - INA3221 Three-Channel Current and Voltage Sensor**

The INA3221 was selected to provide continuous monitoring of both battery packs in the dual battery architecture described in Section 3.3.1. This device was selected because its three independent measurement channels allow both Battery A (powering the Main Compute Unit) and Battery B (powering the Auxiliary Module) to be monitored simultaneously using a single sensor. The third measurement channel is reserved for possible future expansion. This approach avoids the need for two separate single channel monitoring devices.

The INA3221 communicates through the I2C bus, which is managed exclusively by the XIAO ESP32-C3 as described in Section 3.3.1. The sensor provides voltage and current measurements for each battery channel. During normal operation, these readings are forwarded to the Main Compute Unit. During fallback operation, the measurements are directly included in the LoRa fallback beacon, as described in Section 3.3.4.

### **4.1.7 Local Storage - microSD Card**

Each node\'s Raspberry Pi 4B boots from and stores all persistent data, the operating system, the SQLite database described in Chapter 5, and application logs on a microSD card. This is the standard storage mechanism for the Raspberry Pi 4B platform and was not subject to the same comparative selection process as the components above; the specific card capacity and write-endurance class selected for field deployment are documented in Chapter 4\'s deployment specifications.

### **4.1.8 Summary of Selected Components**

  ----------------------- ---------------------------- --------------------------------------------------------- ---------------
  **Component**           **Model**                    **Primary Role**                                          **Interface**
  Main compute platform   Raspberry Pi 4 Model B       Application server, database, DTN sync engine, 5 GHz AP   \-
  Mesh radio              Atheros AR9271 USB adapter   2.4 GHz inter node synchronization backbone               USB
  Auxiliary controller    Seeed Studio XIAO ESP32-C3   GPS, battery monitoring, BLE, LoRa control                USB (to RPi)
  GPS module              GY-GPS6MV2 (u-blox NEO-6M)   Node positioning, UTC time source                         UART
  Long-range radio        HopeRF RFM95 (915 MHz)       LoRa summary transmission, fallback beacon                SPI
  Battery monitor         INA3221                      Dual battery voltage/current monitoring                   I2C
  Storage                 microSD card                 OS, database, application storage                         \-
  ----------------------- ---------------------------- --------------------------------------------------------- ---------------

The Auxiliary Module components listed above; the XIAO ESP32-C3, GY-GPS6MV2, RFM95, and INA3221 are present on DRONE\_A and DRONE\_B only. DRONE\_S\'s hardware configuration is addressed separately in Section 4.1.9.

**4.2 Power System Design**
===========================

As introduced in Section 3.3.1, each drone node uses a dual-battery architecture. In this design, the Main Compute Unit and the Auxiliary Module are powered independently. This arrangement electrically isolates failures between the two sub-units, preventing a failure in one unit from affecting the other. This section presents the detailed power consumption analysis, battery cell configuration, and runtime calculations used to determine the final battery specifications for both sub-units. It also verifies that the design satisfies the main fault-tolerance requirement introduced in Chapter 3: Battery B must provide a longer runtime than Battery A. This ensures that the Auxiliary Module remains operational even after the Main Compute Unit has failed.

![](media/image9.png){width="6.267716535433071in" height="6.527777777777778in"}Figure 4.5: Power system block diagram

**4.2.1 Battery A - Main Compute Unit**

##### **Component Power Consumption**

Battery A supplies power to the Raspberry Pi 4B and the Atheros AR9271 USB Wi-Fi adapter, both operating at 5V. The current consumption of the Raspberry Pi 4B varies depending on its workload. Under the expected moderate workload of simultaneous Wi-Fi access point operation, API serving, database access, and DTN synchronization, a design current value of 1200mA was selected. This value is between the board\'s idle current of approximately 600mA and its peak burst current of approximately 1800mA, which occurs during activities such as simultaneous synchronization and heavy API traffic.

The power consumption of the AR9271 adapter depends on its operating activity, as inter-node synchronization is not continuous. During active transmission and reception, the adapter consumes approximately 450mA, while idle scanning consumes approximately 150mA. Since synchronization activity is estimated to occur for approximately 30% of the operating time, a weighted average current of 240mA was used for runtime calculations. The higher 450mA value was retained for worst-case power converter sizing.

  -------------------- -------------------------- -------------------
  **Component**        **Average Current @ 5V**   **Average Power**
  Raspberry Pi 4B      1200 mA                    6.00 W
  AR9271 USB adapter   240 mA                     1.20 W
  **Total**            **1440 mA**                **7.20 W**
  -------------------- -------------------------- -------------------

##### **Cell Configuration and Buck Converter**

A 2S LiPo configuration was selected for Battery A, providing a nominal voltage of 7.4V with a discharge range of 7.0V to 8.4V. This configuration provides sufficient input voltage above the 5V supply requirement of the Raspberry Pi and AR9271 throughout the complete discharge cycle. As a result, the buck converter can operate efficiently from full charge until the battery reaches its cutoff voltage. A 1S configuration was not suitable because it cannot provide enough voltage to efficiently step up or regulate to the required 5V output. A 3S configuration was also avoided because it would add unnecessary weight and reduce converter efficiency for the given load requirement.

The 7.4V nominal battery output is regulated to a stable 5V supply using a buck converter. The design considers commonly available converters such as the XL4016 or LM2596. The converter efficiency was assumed to be approximately 88% at the expected load level. Considering the conversion losses, the actual input power required from the battery is calculated as:

P\_input = P\_output ÷ η = 7.20 W ÷ 0.88 = 8.18 W

The corresponding average current drawn from the battery at its 7.4V nominal voltage is:

I\_battery = P\_input ÷ V\_battery = 8.18 W ÷ 7.4 V = 1.105 A

##### **Usable Capacity and Depth of Discharge**

To maintain battery lifespan during repeated charge and discharge cycles expected in prototype testing and field deployment, the **Depth of Discharge (DoD)** of both battery packs is limited to **80%**.

For the 2S Battery A pack, this corresponds to a cutoff voltage of 7.0V.

Allowing LiPo cells to discharge beyond this level can accelerate battery degradation and reduce overall capacity. Therefore, deeper discharge was considered unsuitable for this system due to its expected repeated usage cycles.

For a 5000mAh battery cell, the available usable capacity is calculated as:

Usable capacity = 5000 mAh × 0.80 = 4000 mAh = 4.0 Ah

##### **Runtime Calculation**

Runtime = Usable capacity ÷ Average current draw

Runtime = 4.0 Ah ÷ 1.105 A = 3.62 hours ≈ 3 hours 37 minutes

This result satisfies the target operating endurance of 3 to 3.5 hours established for the Main Compute Unit. An earlier version of the design used a 4000mAh cell. With this capacity, the usable capacity was only 3.2Ah, resulting in an estimated runtime of 2.90 hours. Since this did not meet the required endurance target, the final battery specification was revised to use a 5000mAh cell to achieve the required runtime.

##### **Buck Converter Specification**

  --------------------------- ------------------ ------------------------------------------
  **Parameter**               **Value**          **Reason**
  Input voltage range         7.0V -- 8.4V       Full 2S LiPo discharge range
  Output voltage              5.0V ± 2%          Raspberry Pi 4B and AR9271 requirement
  Continuous output current   1440 mA            Total load at 5V
  Converter current rating    3A                 Headroom for DTN sync current peaks
  Efficiency                  \~88%              At this operating point
  Suggested part              XL4016 or LM2596   Widely available, suitable specification
  --------------------------- ------------------ ------------------------------------------

#### **4.2.2 Battery B - Auxiliary Module**

##### **Component Power Consumption**

Battery B supplies power to the XIAO ESP32-C3, RFM95 LoRa module, GY-GPS6MV2 GPS module, and INA3221 battery monitor. All these components operate at 3.3V.

The XIAO ESP32-C3, which handles BLE advertising, GPS data processing, INA3221 polling, and serial communication with the Main Compute Unit during normal operation, was assigned a design current of 80mA. This value represents continuous active operation. The available low power sleep modes of the microcontroller are not used in the current implementation because the module remains active throughout normal operation.

The current consumption of the RFM95 LoRa module depends on its transmission duty cycle, as it does not transmit continuously. According to the module specifications, it consumes approximately 120mA during active transmission at maximum power and 10.3mA during receive/idle operation. Assuming a transmission duration of approximately 2 seconds for every 30 second summary interval, the transmission duty cycle is approximately 6.7%. The weighted average current consumption is calculated as:

Average current = (0.067 × 120 mA) + (0.933 × 10.3 mA) = 8.04 + 9.61 = 17.65 mA

This value was recalculated using the datasheet confirmed RFM95 received current of 10.3mA, replacing the earlier estimate of 15mA used in a previous calculation. The GY-GPS6MV2 GPS module operates continuously to maintain satellite tracking and provide location and time information. A design current of 67mA was selected based on the module selection analysis in Section 4.1.4. This value was originally based on general u-blox NEO-series current consumption data. However, it has not yet been independently verified for the specific GY-GPS6MV2 breakout board, which includes additional components such as onboard voltage regulation and backup battery charging circuitry. Therefore, this value is identified as requiring bench verification before final battery procurement. This verification requirement is also mentioned in the limitations discussed in Chapter 8.

The INA3221 battery monitor consumes a relatively small current of approximately 1mA while continuously measuring both battery channels.

**Normal Mode Total Load**

  ------------------------- ---------------------------- -------------------
  **Component**             **Average Current @ 3.3V**   **Average Power**
  XIAO ESP32-C3             80 mA                        0.264 W
  RFM95 LoRa                17.65 mA                     0.058 W
  GY-GPS6MV2 GPS            67 mA                        0.221 W
  INA3221                   1 mA                         0.003 W
  **Total (normal mode)**   **165.65 mA**                **0.546 W**
  ------------------------- ---------------------------- -------------------

**Fallback Mode Total Load**

In fallback mode, as described in Section 3.3.4, BLE advertising and USB serial communication are disabled. As a result, the ESP32-C3\'s own current consumption is reduced to an estimated 50mA. However, the LoRa module, GPS module, and battery monitoring system continue operating at the same current levels used during normal operation. This is because these functions are essential for generating and transmitting the fallback beacon. The fallback beacon relies on the continued availability of location data, battery status information, and LoRa communication, making these components necessary even after the Main Compute Unit has failed.

  ----------------------------------- ----------------------------- --------------------
  **Component**                       **Fallback Current @ 3.3V**   **Fallback Power**
  XIAO ESP32-C3 (no BLE, no serial)   50 mA                         0.165 W
  RFM95 LoRa                          17.65 mA                      0.058 W
  GY-GPS6MV2 GPS                      67 mA                         0.221 W
  INA3221                             1 mA                          0.003 W
  **Total (fallback mode)**           **135.65 mA**                 **0.447 W**
  ----------------------------------- ----------------------------- --------------------

##### **Cell Configuration and Regulation**

A 1S LiPo configuration was selected for Battery B, providing a nominal voltage of 3.7V with a discharge range of 3.5V to 4.2V. Since all components in the Auxiliary Module operate at 3.3V, this single cell battery can be regulated directly to the required voltage using the XIAO ESP32-C3\'s onboard AMS1117-3.3V linear regulator. Unlike Battery A, no external buck converter is required. This simplifies the Auxiliary Module\'s power circuitry and helps reduce its weight, complexity, and cost. This approach is appropriate because the Auxiliary Module has a relatively low and stable power demand compared to the Main Compute Unit. The efficiency of the linear regulator at the nominal battery voltage is calculated as:

η\_LDO = V\_out ÷ V\_in = 3.3 V ÷ 3.7 V = 89.2%

The voltage difference of approximately 0.4V is dissipated as heat by the regulator. At the current levels consumed by the Auxiliary Module, this heat generation is not expected to create a significant thermal concern.

##### **Usable Capacity**

Applying the same 80% Depth of Discharge (DoD) limit used for Battery A helps maintain consistent battery longevity across both battery packs. For a 2500mAh cell, the usable capacity is therefore limited to 80% of the nominal capacity. The usable capacity is calculated as:

Usable capacity = 2500 mAh × 0.80 = 2000 mAh = 2.0 Ah

##### **Runtime Calculations**

Normal mode runtime = 2.0 Ah ÷ 0.16565 A = 12.08 hours

Fallback mode runtime = 2.0 Ah ÷ 0.13565 A = 14.74 hours

Both calculated runtimes exceed the 12 hour fallback endurance target established for the Auxiliary Module. An earlier version of the design specified a 1000mAh cell for Battery B. With an 80% Depth of Discharge limit, this provided a usable capacity of only 0.8Ah. At this capacity, the estimated fallback runtime was approximately 5.71 hours, which is less than half of the required target. To address this shortfall, the final battery specification was revised to use a 2500mAh cell, ensuring that the Auxiliary Module can achieve the required operating endurance during fallback operation.

#### **4.2.3 Battery Independence Verification**

A key requirement of the dual battery architecture, introduced in Section 3.3.1, is that Battery B must remain operational longer than Battery A. This ensures that the Auxiliary Module can continue transmitting fallback health beacons even after the Main Compute Unit has lost power or otherwise failed.

The calculated runtimes are:

-   Battery A runtime: 3.62 hours

-   Battery B fallback runtime: 14.74 hours

-   Runtime margin: 11.12 hours

These results confirm that Battery B significantly outlasts Battery A under the assumptions used in the design calculations. Therefore, the system satisfies the fault tolerance requirement that motivated the adoption of the dual battery architecture. The Auxiliary Module can continue operating and transmitting fallback information for a considerable period after the Main Compute Unit becomes unavailable.

#### **4.2.4 Complete Power System Summary**

  -------------------------- ---------------------------- -------------------------------------------
  **Parameter**              **Battery A**                **Battery B**
  Powers                     RPi 4B + AR9271              ESP32-C3 + LoRa + GPS + INA3221
  Chemistry                  LiPo                         LiPo
  Configuration              2S                           1S
  Nominal voltage            7.4V                         3.7V
  Voltage range              7.0V -- 8.4V                 3.5V -- 4.2V
  Recommended capacity       5000 mAh                     2500 mAh
  Depth of Discharge limit   80%                          80%
  Usable capacity            4.0 Ah                       2.0 Ah
  Average current draw       1105 mA                      165.65 mA (normal) / 135.65 mA (fallback)
  Regulation                 Buck converter (7.4V → 5V)   Onboard LDO (3.7V → 3.3V)
  Regulator efficiency       \~88%                        \~89.2%
  Expected runtime           3.62 hours                   12.08 hr (normal) / 14.74 hr (fallback)
  BMS                        External BMS required        Built into XIAO ESP32-C3
  Monitored via              INA3221 CH1                  INA3221 CH2
  Electrically isolated      Yes                          Yes
  -------------------------- ---------------------------- -------------------------------------------

![](media/image10.png){width="6.267716535433071in" height="2.5416666666666665in"}Figure 4.6: Runtime comparison bar chart

Note on the demonstration prototype: The battery specification presented above is the target design based on the power calculations in this section. For the demonstration prototype, a smaller battery configuration was used to reduce cost. Battery A uses a 2S 2500mAh battery with a 5A BMS, and Battery B uses a 1S 1500mAh battery with a 3A BMS. The original design specifies 5000mAh for Battery A and 2500mAh for Battery B. Using the same average current values calculated in this section, the smaller batteries provide an estimated runtime of about 1 hour 49 minutes for Battery A and about 8 hours 51 minutes for Battery B. Although the backup time is reduced from about 11 hours to about 7 hours, Battery B still lasts longer than Battery A. This meets the main fault-tolerance requirement described in Section 4.2.3. The larger battery specification remains the intended design for real deployments. The smaller batteries were used only for the demonstration prototype because of cost constraints and do not change the original design target.

**4.3 Main Compute Unit**
-------------------------

This section describes the physical hardware integration of the Main Compute Unit, including the Raspberry Pi 4 Model B, the Atheros AR9271 USB Wi-Fi adapter, the power supply arrangement, and the physical connection to the Auxiliary Module. In accordance with the architectural boundary established in Chapter 3, this section focuses only on the physical and electrical integration of these components. The software components running on the Main Compute Unit, including the FastAPI application, the DTN synchronization engine, and the auxiliary bridge software, are discussed separately in Chapter 5.

![](media/image11.png){width="5.958333333333333in" height="2.484288057742782in"}

Figure 4.3 - Main Compute Unit Physical Connection Diagram

#### **4.3.1 Physical Port Allocation**

The Raspberry Pi 4 Model B provides four USB ports, consisting of two USB 2.0 ports and two USB 3.0 ports, in addition to its onboard dual band Wi-Fi radio. Since the board must simultaneously support the onboard access point radio, the external mesh radio, and the serial connection to the Auxiliary Module, a fixed port allocation was defined to ensure consistent operation across all deployed nodes.

The onboard Wi-Fi radio does not require a USB connection because it is integrated directly into the Raspberry Pi hardware. This radio operates in access point mode, as described in Section 3.2.4, and remains permanently configured during normal operation.

The Atheros AR9271 USB Wi-Fi adapter is connected to one of the USB 3.0 ports. A USB 3.0 port was selected intentionally because the Raspberry Pi 4B connects its USB 3.0 ports through a separate internal bus from the USB 2.0 ports. This reduces the possibility of bus contention between the mesh radio\'s continuous network traffic and other USB activities. The second USB 3.0 port is allocated to the serial connection with the Auxiliary Module, described in Section 3.3.2. This connection uses a standard USB-A to USB-C cable. The USB-A connector is attached to the Raspberry Pi, while the USB-C connector is connected to the native USB port of the XIAO ESP32-C3.

The two USB 2.0 ports remain unused during normal field operation. However, they are retained for development, debugging, and initial node setup activities, where temporary peripherals such as a keyboard, mouse, or diagnostic device may need to be connected.

#### **4.3.2 Power Input**

The Main Compute Unit is powered by Battery A, the dedicated LiPo battery pack whose capacity, discharge characteristics, and runtime calculations were presented in Section 4.2. Power from Battery A is supplied through the buck converter specified in the same section. The converter reduces the battery\'s nominal 7.4V output to the 5V supply required by the Raspberry Pi. The regulated 5V output is provided to the Raspberry Pi through its USB-C power input, which is the standard power input connector used on this board revision.

The AR9271 USB Wi-Fi adapter receives power directly from the Raspberry Pi\'s USB bus, following normal USB device operation. It does not have a separate power connection to Battery A. As a result, the adapter\'s power consumption, which was already included in the Section 4.2 power budget, is supplied through the Raspberry Pi and forms part of the total load placed on Battery A. Therefore, the AR9271 does not act as an independent load on the power system. Its current consumption is included within the overall power demand of the Main Compute Unit.

#### **4.3.3 Physical Mounting Considerations**

The Raspberry Pi 4B and the AR9271 USB Wi-Fi adapter are mounted together within the enclosure section allocated to the Main Compute Unit, as illustrated in the enclosure design presented in Section 4.5. The AR9271 adapter, which uses a USB dongle style form factor, is positioned so that its onboard antenna has a relatively clear path through the enclosure wall. This arrangement helps reduce signal attenuation and supports reliable operation of the 2.4 GHz mesh backbone described in Section 3.2.4.

The Raspberry Pi\'s onboard Wi-Fi antenna is integrated directly into the board and cannot be repositioned independently. To accommodate this limitation, the enclosure design described in Section 4.5 places the Raspberry Pi in an orientation that keeps the antenna away from nearby metallic components and dense cabling. This helps minimize potential interference and supports the performance of the 5 GHz access point used for user connectivity.

#### **4.3.4 Interface Summary**

  --------------------- --------------------------------------------- --------------------------------------------------------
  **Interface**         **Connected To**                              **Purpose**
  Onboard Wi-Fi radio   \- (internal)                                 5 GHz Access Point - user and rescue team connectivity
  USB 3.0 (Port 1)      Atheros AR9271 adapter                        2.4 GHz mesh backbone (inter-node DTN sync)
  USB 3.0 (Port 2)      XIAO ESP32-C3                                 Serial link to Auxiliary Module
  USB 2.0 (×2)          Unused (field)                                Reserved for development and diagnostics
  USB-C power input     Battery A (via buck converter, Section 4.2)   5V regulated power supply
  microSD slot          microSD card                                  OS, database, and application storage
  --------------------- --------------------------------------------- --------------------------------------------------------

**4.4 Auxiliary Module**
------------------------

This section applies to DRONE\_A and DRONE\_B only, both of which carry the Auxiliary Module hardware. DRONE\_S\'s hardware configuration, which omits this module, is addressed in Section 4.1.9. It describes the physical hardware integration of the Auxiliary Module, including the Seeed Studio XIAO ESP32-C3, the GY-GPS6MV2 GPS module, the RFM95 LoRa transceiver, the INA3221 battery monitor, and the power supply arrangement provided by Battery B. Similar to Section 4.3, this section focuses only on the physical and electrical integration of these components. The firmware running on the XIAO ESP32-C3, including the GPS parsing logic, LoRa transmission control, BLE advertising functionality, and the serial communication protocol used to interact with the Main Compute Unit, is discussed separately in Chapter 5.

![](media/image12.png){width="6.267716535433071in" height="2.8333333333333335in"}

Figure 4.9: Auxiliary Module physical connection diagram

#### **4.4.1 Physical Interface Allocation**

The XIAO ESP32-C3 provides a limited but sufficient number of GPIO pins through its castellated edges. These pins are used to allocate the required UART, SPI, and I2C interfaces for the Auxiliary Module\'s sensor and communication components. Since the microcontroller must simultaneously communicate with three external devices, maintain the USB serial connection with the Raspberry Pi, and operate its built in BLE radio, a fixed pin allocation was defined. This approach avoids peripheral conflicts and ensures consistent wiring across all three deployed nodes.

The GY-GPS6MV2 GPS module is connected to a dedicated UART peripheral on the XIAO ESP32-C3. It operates at the module\'s default baud rate of 9600 bps, as described in Section 4.1.4. This is a direct point to point serial connection using only the transmit (TX) and receive (RX) lines, along with shared 3.3V power and ground connections. The GPS module does not require additional control signals because it only provides serial output data.

The RFM95 LoRa module is connected to the XIAO ESP32-C3\'s SPI peripheral. The SPI interface is required for the RFM95\'s register configuration and packet transmission operations. In addition to the standard SPI lines (MOSI, MISO, and SCK), the RFM95 requires a dedicated chip-select line and a reset line, which are assigned to available GPIO pins. An optional interrupt line is also connected to allow the module to indicate packet reception events without requiring continuous polling from the ESP32-C3.

The INA3221 battery monitor is connected to the XIAO ESP32-C3\'s I2C peripheral. It uses the standard I2C signal lines, SDA and SCL, which are shared between I2C devices. Since the INA3221 is the only I2C device used in this design, no address conflicts occur, and the device operates using its default I2C address.

The native USB-C port of the XIAO ESP32-C3 is used for two purposes: power delivery during standalone testing and the serial communication link described in Section 3.3.2. It is connected to one of the Raspberry Pi\'s USB 3.0 ports using a USB-A to USB-C cable, as described in Section 4.3.1. However, during normal field deployment, the USB-C power supply capability is not used. Instead, the Auxiliary Module receives power independently through its battery input connection, described in Section 4.4.2. This maintains the electrical isolation principle established in Section 3.3.1, where the Main Compute Unit and Auxiliary Module operate using separate power sources.

#### **4.4.2 Power Input**

The Auxiliary Module receives power from Battery B, the dedicated 1S LiPo battery pack whose capacity, discharge characteristics, and runtime calculations were presented in Section 4.2.2. Battery B is connected directly to the battery input pin of the XIAO ESP32-C3. The XIAO ESP32-C3 board includes an onboard battery charging circuit and the AMS1117-3.3V linear regulator discussed in Section 4.2.2. This allows Battery B to be charged and regulated to the required 3.3V supply rail for the XIAO ESP32-C3 and its connected peripherals, including the GY-GPS6MV2, RFM95, and INA3221, without requiring additional external power circuitry.

Unlike the Main Compute Unit, which uses a buck converter based power path described in Section 4.3.2, the complete power system of the Auxiliary Module is integrated into the XIAO ESP32-C3 board. This includes battery charging, protection, and voltage regulation. This design follows the approach described in Section 4.2.2, where the Auxiliary Module is kept simple, lightweight, and low cost due to its comparatively lower power requirement.

It is important to note that this power path is completely independent of the Raspberry Pi\'s USB-C connection described in Section 4.4.1. Although a USB cable physically connects the two sub-units, the Auxiliary Module does not receive operating power through this connection during normal field deployment. Instead, the XIAO ESP32-C3 and all connected peripherals are powered only by Battery B. This separation is important for the fault tolerance design described in Section 3.3 and verified in Section 4.2.3. The Auxiliary Module must be able to continue operating in fallback mode without depending on any power supplied by, or passing through, the Main Compute Unit.

#### **4.4.3 Physical Mounting Considerations**

The XIAO ESP32-C3 and its three connected peripherals are mounted together within the enclosure section allocated to the Auxiliary Module. This section is physically separated from the Main Compute Unit layer, as shown in the enclosure design presented in Section 4.5. This physical separation strengthens the electrical and functional independence between the two sub units at the hardware layout level, rather than only through the wiring design.

The external U.FL connected ceramic antenna of the GY-GPS6MV2 is routed to the dedicated GPS antenna position on the outer surface of the enclosure, as identified in Section 4.5. This placement improves satellite visibility when the drone node is mounted on a drone frame. Similarly, the RFM95 LoRa antenna requires a clear signal path for effective long range communication. Therefore, it is positioned within the enclosure to reduce obstruction from other internal components and improve transmission performance. The INA3221 does not require an external antenna or radio connection. It is mounted with its sensing connections routed to the terminal points of both Battery A and Battery B, as shown in the power system diagram in Section 4.2.

#### **4.4.4 Interface Summary**

![](media/image13.png){width="6.267716535433071in" height="2.861111111111111in"}

Figure 4.10: XIAO ESP32-C3 pinout diagram

  ---------------------------------- ----------------------------------------------------------- --------------------------------------------------------
  **Interface**                      **Connected To**                                            **Purpose**
  UART                               GY-GPS6MV2                                                  GPS location and UTC time acquisition
  SPI (MOSI/MISO/SCK/CS/RESET/IRQ)   RFM95 LoRa module                                           Long-range summary and fallback beacon transmission
  I2C (SDA/SCL)                      INA3221                                                     Dual-battery voltage and current monitoring
  Onboard BLE radio                  --- (internal)                                              User discovery advertisement
  USB-C                              Raspberry Pi 4B (USB 3.0 Port 2)                            Serial data link (heartbeat, JSON telemetry, commands)
  Battery input pin                  Battery B (direct, via onboard charge/regulation circuit)   3.3V power for ESP32-C3 and all connected peripherals
  ---------------------------------- ----------------------------------------------------------- --------------------------------------------------------

**4.5 Enclosure Design**
------------------------

**4.6 Mounting System**
-----------------------

**Chapter 5: SoftwareDesign**
=============================

### **5.1 Wi-Fi Access and Captive Portal**

This section describes the software responsible for the User Access Layer\'s networking behaviour, introduced conceptually in Section 3.2.1. It explains the HTTP captive portal, how it handles platform specific captive portal detection, and its message submission and validation process. This functionality is implemented in the http\_app.py module of the **local-server** repository. It runs as an independent FastAPI service on port 80 and operates separately from the authenticated HTTPS service described in Section 5.4.

#### **5.1.1 Design Rationale - the \"Victim Plane\"** 

As established in Section 3.2.1, this service deliberately handles the entire victim facing workflow over plain, unencrypted HTTP. This includes the submission form, message submission, and Emergency Application check-ins, all served from the same origin. For this part of the system, message integrity and availability are given higher priority than confidentiality. The reasoning is that an unencrypted but successfully delivered request for help is more valuable than a request that never reaches rescuers because a user could not proceed past a certificate warning. Every message accepted by the service is still cryptographically signed when it is received, as described in Section 5.1.4. This ensures that the message cannot be modified after submission, even though the transport itself is unencrypted. The reasoning behind this design choice and its role within the overall security model are discussed in Section 5.8.

#### **5.1.2 Captive Portal Detection Across Platforms**

Modern operating systems detect a captive portal by sending a background request immediately after connecting to a new Wi-Fi network. They expect a specific response if the network provides normal internet access. If the response is different, the operating system assumes that a captive portal is present. Since Android, iOS, and Windows each use different probe URLs and expect different responses, http\_app.py handles each platform separately instead of using a single generic captive portal mechanism.

Android sends its probe request to /generate\_204, while iOS uses /hotspot-detect.html. Both requests are answered by returning the victim message form directly. Since the returned content is different from what these operating systems expect, they display their captive portal notification. In both cases, the user is taken directly to the message submission form without any intermediate page.

Windows sends its probe request to /ncsi.txt and, on newer versions, /connecttest.txt. It expects the exact text Microsoft NCSI. Instead, the system returns a short, different plain-text response. This causes Windows to recognize that a captive portal is present and display its network sign in notification. Unlike Android and iOS, these Windows probe endpoints do not return the submission form directly. Instead, the user opens the sign in window provided by Windows, which requests the root page and receives the victim message form.

Any other unrecognized request made by a connected device is handled by a catch all route, which returns the same victim message form. The only exceptions are the reserved API endpoints (/message, /checkin, and /victim-public-key). These are excluded from the catch all route so that invalid requests to these endpoints return the correct error instead of being redirected to the submission form.

![](media/image14.png){width="6.267716535433071in" height="3.5694444444444446in"}

Figure 5.1: Sequence diagram of captive portal detection and redirect

#### **5.1.3 Security Headers and Rate Limiting** 

Every response sent by this module passes through a middleware layer that adds several security headers. These include a restrictive Content Security Policy, X-Content-Type-Options: nosniff, X-Frame-Options: DENY, and Referrer-Policy: no-referrer. These headers limit the ability of the page to load external resources, prevent the page from being embedded by another website, and reduce the possibility of leaking referrer information. These protections are applied even though the page itself is served without transport encryption.

Since this service accepts messages from any device connected to the node\'s Wi-Fi without authentication, it could be targeted by flooding attacks that attempt to fill the message database with unnecessary data. To reduce this risk, two separate rate limiting mechanisms are applied to every submission.

-   The first is a sliding window limiter that controls the number of submissions from a single client IP address.

-   The second is a global limiter that restricts the total number of unauthenticated submissions received by the node, regardless of the number of devices involved. If a submission exceeds either limit, it is rejected before reaching the database layer.

#### **5.1.4 Input Validation and Message Signing** 

All submitted data is checked using a set of Pydantic models before it is accepted by the system. Plaintext message content is HTML escaped and limited to a maximum of 800 characters. If client side encryption is used, as described in Section 5.1.5, the content is instead checked as valid base64 data and allowed up to 8192 characters to accommodate the larger ciphertext size. Optional GPS coordinates provided by the user\'s browser are also validated to ensure they fall within valid latitude and longitude ranges. Any submission that fails these checks is rejected with a validation error and does not reach the database.

Every message that passes validation is cryptographically signed by the node backend when it is stored. The same signing mechanism is also used for records exchanged during inter-node synchronization, as described in Section 5.2. This signature allows the integrity of the message to be verified later by other nodes during synchronization or by authenticated clients accessing the data. This protection remains effective even though the original message was received through an unencrypted connection.

#### **5.1.5 Optional Client Side Encryption**

Independently of the transport level decision described in Section 5.1.1, the system also supports optional encryption of the message content before submission. This encryption is performed directly in the victim\'s browser using RSA-OAEP with a public key obtained from a dedicated endpoint. This feature is disabled by default and is not required for a message to be submitted successfully. When it is enabled through node configuration, the client side script retrieves the current public key and encrypts the message content using the browser\'s built in Web Crypto API. The submission is then marked as encrypted, allowing the backend to identify whether the received content is encrypted or plaintext during validation, as described in Section 5.1.4. The purpose of this feature, its default disabled state, and the reasons behind this design choice are discussed in the security architecture in Section 5.8.

#### **5.1.6 Victim Session Continuity**

To help rescue teams confirm a user\'s identity after physically locating them, the victim form generates a random device identifier when it is used for the first time. This identifier is stored in the browser\'s local storage, allowing it to remain available across multiple visits from the same device. A shortened version of this identifier is displayed on the form as a reference code. The user can keep this code and provide it to rescue personnel when they are contacted. The same identifier is included with every message and check-in submitted from that device, allowing multiple submissions from the same device to be linked together when required.

#### **5.1.7 Emergency Application Integration**

In addition to direct form submission, this module provides two endpoints used only by the Emergency Application described in Section 3.2.5 and further explained in Section 5.7. The first is a check-in endpoint that accepts a group of previously recorded location points from the application, along with an optional urgent flag. When the urgent flag is enabled, the system also creates a normal victim message alongside the check-in data. This ensures that the request follows the same rescue workflow as any other submission, regardless of how it was created.

The second endpoint is a simple connectivity probe endpoint used by the Emergency Application. It allows the application to confirm that it is connected to an actual drone node\'s Wi-Fi access point before responding to a BLE detection event. This endpoint was introduced after an issue in an earlier version of the application, where it attempted to check the authenticated /health endpoint described in Section 5.4. Since that endpoint does not exist on this unauthenticated service, the application incorrectly determined that it was not connected to a drone network. The probe endpoint only provides the node identifier and Wi-Fi network name, which are already available from the BLE advertisement. This follows the overall design principle that no victim data can be accessed through this unauthenticated service.

**5.2 Inter-Node Synchronization Mechanism**
--------------------------------------------

This section describes the software that implements the ad-hoc mesh synchronization behaviour introduced conceptually in Sections 3.2.2 and 3.3.5. This functionality is implemented as a single background process called sync\_daemon.py, which runs continuously on each node\'s Main Compute Unit. It completely replaces the switcher.py script used in Phase 1. Since the mesh radio now remains permanently connected to a fixed ad-hoc network, as described in Chapter 4, there is no longer any need for the network interface switching performed by the earlier script.

![](media/image15.png){width="4.854779090113736in" height="4.81372375328084in"}

Figure 5.3: sync\_daemon.py internal structure

The daemon performs three tasks at the same time. Each task runs as a separate thread within the same process. One thread periodically broadcasts the node\'s presence beacon. Another listens for and validates beacons received from neighbouring nodes. The third periodically requests and retrieves missing data from every peer that is currently considered reachable.

### **5.2.1 Presence Beacons**

Every ten seconds, each node broadcasts a compact, signed UDP datagram to a fixed broadcast address on the ad-hoc subnet described in Chapter 4, using port **48555**. The beacon contains the node\'s identifier, the API service port, a timestamp, a continuously increasing counter, and a summary of the number of records currently stored in each of the five replicated tables described in Section 5.2.3. The beacon is signed using a cryptographic key dedicated only to inter-node authentication, as described in Section 5.2.4.

When a node receives a beacon, it first verifies the cryptographic signature. If the verification fails, the beacon is immediately discarded and the event is recorded in the log. If the signature is valid, the node then checks the beacon\'s counter against the most recent counter received from the same sender. If the counter has not increased, the beacon is treated as a replayed or duplicate packet. It is rejected, logged, and not used to update the sender\'s status. If both checks succeed, the receiving node updates its local list of known peers with the sender\'s address, API port, and the time the beacon was received.

A peer is considered reachable only while valid beacons continue to arrive within a 35 second time window. If no valid beacon is received during this period, the peer is marked as unreachable and is excluded from the pull synchronization process described in the next section. It becomes reachable again only after another valid beacon is received. Using a 10 second beacon interval with a 35 second timeout allows the system to tolerate the loss of two or three consecutive beacons, which may occur because of temporary wireless interference, without incorrectly marking an active peer as unavailable.

### **5.2.2 Pull Synchronization Loop**

Separate from the beacon mechanism, another synchronization process runs every thirty seconds. During this process, each node attempts to synchronize with every peer currently listed as reachable in its alive peer table. For each peer, the node checks each of the five replicated tables described in Section 5.2.3 and requests only the records that are new or updated since the last successful synchronization with that specific peer and table.

This is managed using a separate synchronization cursor for each peer and table combination. The node stores the timestamp of the latest record it successfully received from each peer for each table. During the next synchronization request, this timestamp is sent as a parameter, allowing the peer to return only the changes that occurred after that point. This avoids sending the complete table contents during every synchronization cycle.

Each synchronization request includes a shared authentication value in a custom header. The receiving node verifies this value before providing any data. This ensures that only trusted nodes can request synchronized data, even if another device is connected to the same ad-hoc network. The authentication value is generated using the same inter node key used for signing presence beacons, as described in Section 5.2.4, rather than relying on a fixed static secret.

Synchronization of the five tables is handled independently. If a problem occurs while retrieving or processing one table, such as a network failure, unreachable peer, or invalid response, the issue is recorded in the log, but synchronization of the remaining tables continues. This prevents a temporary issue affecting one type of data, such as Emergency Application check in records, from blocking the synchronization of more critical information such as victim messages or personnel credentials.

### **5.2.3 Replicated Tables and Conflict Resolution**

Five tables participate in synchronization: victim messages, personnel credentials, announcements, ground station field reports, and Emergency Application check in records. Every record received from a peer is first verified using its embedded cryptographic signature before it is considered for storage. If the verification fails, the record is immediately discarded and the rejection is logged, regardless of the table it belongs to.

For records that pass verification, the method used to compare and update data depends on the specific table involved.

Victim messages follow a claimed status precedence rule. A locally stored message that is already marked as claimed cannot be overwritten by an incoming record that is still marked as new. If both records are already claimed, which may happen when two rescue personnel independently claim the same message before synchronization occurs, the earlier claim based on the claim timestamp is retained. The identity of the rescue team member who made the earlier claim is also preserved. However, if an incoming record shows that a message has been claimed while the local record is still marked as new, the incoming record is accepted and the local record is updated.

Personnel credentials follow a similar precedence rule based on revocation status. A credential that has already been revoked locally cannot be restored by an incoming record that does not include the revocation status. If neither record is revoked, the version with the latest update timestamp is retained, allowing normal profile updates to propagate between nodes.

Announcements, ground station field reports, and Emergency Application check in records are handled as append only data. These records do not have status changes like message claims or credential revocations. Therefore, synchronization only ensures that records created on one node are eventually copied to all other nodes. If a record with the same primary key already exists locally, it is kept unchanged without further comparison or merging.

Whenever a record is accepted into a node\'s database, either as a new record or as an update based on the rules above, it receives a new local timestamp at the time of acceptance. This timestamp allows the record to continue propagating through the network. When another node later synchronizes with this node, it can identify the record as new within its own synchronization window. This ensures that store and forward propagation continues to work correctly, even when the record originally came from a different node in the network.

### **5.2.4 Purpose Separated Cryptographic Keys**

An earlier version of the system used one shared secret for all cryptographic operations. This single secret was used for signing replicated records, authenticating communication between nodes, and was also considered for use with personnel session tokens. During the security review discussed in Section 5.8, this approach was identified as a weakness. If one node was compromised, the attacker could potentially gain access to a secret capable of affecting every cryptographic function in the system.

The current implementation uses separate cryptographic keys for each purpose. These keys are generated from a single master secret using HKDF with SHA-256. Each derived key is linked to a specific purpose using a fixed context string. One key is used only for signing replicated records across the five synchronized tables described in Section 5.2.3. A second key is used only for communication between nodes, including the presence beacon signatures described in Section 5.2.1 and the authentication headers used during pull synchronization in Section 5.2.2. A third key, described further in Section 5.6, is used only for signing personnel session tokens.

Since each key is generated separately using a different purpose string, the compromise of one key does not directly allow an attacker to forge data protected by the other keys. However, because all keys are ultimately derived from the same master secret, physical capture of a node could still expose the master secret itself. The response procedure for such an event, including fleet-wide key rotation, is discussed in Section 5.8.

**5.3 Auxiliary Module Firmware**
---------------------------------

This section describes the firmware running on the XIAO ESP32-C3 Auxiliary Module. This module is used on DRONE\_A and DRONE\_B, as established in Chapter 3 and Chapter 4. The firmware is implemented as a single Arduino framework codebase that is flashed onto both modules. The two modules are distinguished only by a node identifier that is assigned to each board during initial setup. This firmware implements the sensor collection and fallback beacon functions introduced in Sections 3.3.1, 3.3.3, and 3.3.4.

![](media/image16.png){width="6.267716535433071in" height="7.930555555555555in"}Figure 5.4: Firmware state machine

### **5.3.1 Firmware Structure and Peripheral Initialization**

The firmware follows a single loop, non blocking design commonly used in Arduino framework projects. Instead of using separate execution threads for each peripheral, a single loop() function handles all operations. During each loop cycle, the firmware checks the GPS serial data, the Raspberry Pi serial connection, and the LoRa receiver. Periodic tasks, such as sending sensor updates or transmitting fallback beacons, are controlled using elapsed time checks instead of blocking delays.

During startup, the firmware initializes all required hardware interfaces. These include the native USB serial connection to the Raspberry Pi, the serial interface for the GPS module, the I2C bus for the INA3221 battery monitor, and the SPI bus with the required settings for the RFM95 LoRa module. After initialization, the firmware loads the node identifier and the last received message from persistent flash storage and starts BLE advertising.

One pin assignment differs from the original design specification due to changes made during hardware testing. The LoRa module\'s MISO line was initially planned for a different GPIO pin. However, during the first hardware tests, this pin failed to provide valid SPI communication. It was therefore moved to another GPIO pin that was verified to work correctly. This modification is documented in the firmware source code and the project change log.

The LoRa radio is configured for 915 MHz operation with a spreading factor of 7 and a bandwidth of 125 kHz, following the module selection described in Chapter 4. The transmission power is intentionally set to the minimum level supported by the radio library rather than using the maximum rated output of the module. This limitation remains in place until the applicable regulatory requirements for this frequency band in the intended deployment region are confirmed. This requirement is also identified as a limitation discussed in Chapter 8 and should not be changed for range testing before confirmation.

### **5.3.2 Operating State Machine**

The firmware operates using a three state machine. These states are an initialization state that runs once during startup, a normal operating state where the module works as a sensor feeder, and a fallback state that is entered when the Main Compute Unit failure is detected. This behaviour follows the operating principles described in Sections 3.3.3 and 3.3.4. Since the Raspberry Pi may require some time to complete its boot process and start sending heartbeat signals, the firmware provides a longer waiting period for the first heartbeat after startup. After the first heartbeat is received, the firmware uses a shorter timeout period for all later heartbeat checks. This prevents a slow starting Main Compute Unit from being incorrectly identified as failed immediately after power up.

The transition from normal operation to fallback mode is intentionally one way during a single power cycle. Once fallback mode is activated, the Auxiliary Module does not automatically return to normal operation, even if heartbeat signals from the Main Compute Unit appear again. This decision is based on the assumption that a Main Compute Unit that has already failed during a deployment should not be automatically trusted without manual inspection or a power cycle. This behaviour is a deliberate design choice rather than a missing feature. The firmware already contains the basic logic required to support automatic recovery in the future if this operating behaviour is changed.

### **5.3.3 Normal Mode Sensor Feeding**

While operating in the normal state, the module continuously processes incoming GPS data in the background. At a fixed interval, it sends the current GPS information and battery readings from both INA3221 monitoring channels to the Main Compute Unit through the serial connection. These values are sent as separate, structured JSON messages. Once the GPS module provides a valid date, time, and location fix, the Auxiliary Module also provides the GPS derived UTC time to the Main Compute Unit. This information is sent periodically rather than continuously because the Main Compute Unit only needs occasional updates to maintain accurate time synchronization, as described in Section 5.2 and Chapter 3.

BLE advertising remains active continuously during normal operation. It works independently from the Raspberry Pi serial connection. This allows users to discover the drone node even if the Main Compute Unit is experiencing communication issues. During development, an important BLE implementation issue was identified. The Emergency Application described in Sections 3.2.5 and 5.7 uses Android background scanning to detect nearby nodes while the phone screen is off. Android\'s BLE scan filtering checks the complete list of advertised service UUIDs, but it does not match the same information when it is placed only inside a service data field. An earlier firmware version stored the node identification UUID only inside the service data field. As a result, the Emergency Application\'s background scan filter could not detect the advertisement, even though the advertisement was visible using general Bluetooth scanning tools. This issue was identified during testing and corrected by separating the advertisement data into two parts. The main advertisement now includes the service UUID required by Android\'s filtering system, while the smaller node and network identifier data is included in the scan response frame.

### **5.3.4 Serial Protocol**

Communication between the Auxiliary Module and the Main Compute Unit uses newline delimited JSON messages in both directions through the native USB serial connection. This matches the physical integration described in Chapter 4. Messages sent from the Auxiliary Module to the Main Compute Unit include different message types for reporting GPS location data, GPS derived time, battery readings, received LoRa messages during normal operation, received fallback beacons from other nodes, and confirmation of successful message caching. Messages sent from the Main Compute Unit to the Auxiliary Module include heartbeat signals, requests to update the BLE advertisement information after a change in node identity or network name, newly received message content that needs to be stored locally, commands to transmit periodic LoRa status summaries, and the assignment of the persistent node identifier during the initial setup process.

The Main Compute Unit handles this communication through a dedicated bridge process. This process is designed to operate even when an Auxiliary Module is not available. On DRONE\_S, which does not include an Auxiliary Module, the bridge process detects that the expected serial device is missing, records this condition, and stops running without affecting any other node functionality.

### **5.3.5 Fallback Beacon Transmission**

When the module enters the fallback state, it immediately sends its first beacon. After that, it continues transmitting the beacon at a fixed interval. The beacon follows the compact pipe delimited format introduced in Section 3.3.4. The beacon contains the node identifier, GPS coordinates and fix status (when available), GPS derived UTC time (when available), voltage and current readings from both battery channels, and the cached last message with its timestamp. Before transmission, the message content is processed to remove the field separator character and is shortened if necessary to ensure that the complete beacon remains within the allowed size limit. If a specific value is not available at the time of transmission, the corresponding field is left empty instead of stopping the transmission completely. For example, GPS coordinates may be unavailable before the module obtains a satellite fix. This approach allows partial but useful information to continue reaching the network even when some sensors are unavailable. BLE advertising is disabled for the rest of the fallback state to reduce power consumption and preserve Battery B\'s remaining capacity. This behaviour follows the design reasoning described in Section 3.3.4 and the power analysis presented in Chapter 4.

**5.4 Local API Server**
------------------------

This section describes api.py, the authenticated HTTPS service running on each node\'s Main Compute Unit. This service provides access to node data for the rescue personnel application, the Ground Control Center, and the inter node synchronization process. This service is completely separate from the unauthenticated victim facing system described in Section 5.1. It runs on a different port and uses HTTPS communication. As established in Chapter 3, the service is protected using certificates issued by a fleet wide certificate authority during deployment. The details of this security approach are discussed further in Section 5.8.

![](media/image17.png){width="6.267716535433071in" height="6.597222222222222in"}

Figure 5.5: Authentication precedence diagram

### **5.4.1 Authentication and Role Resolution**

Every request received by this service is assigned one of four roles: USER, RESCUE\_TEAM, HQ, or SYNC\_NODE. These roles follow the access model defined in Chapter 3. The service does not require clients to specify which authentication method they are using. Instead, it checks the available credentials in a fixed order and uses the first valid method it finds.

The inter node authentication header is checked first. This header is only included in requests sent by another node\'s synchronization process. If the header is present, it is verified using the shared inter node authentication value derived in Section 5.2.4. If verification fails, the request is rejected immediately and is not checked against any other authentication method. If no inter node header is provided, the service checks for a session token, which is described further in Section 5.4.2. If a valid session token is not present, the service then checks for a static, labelled API key. This API key is not intended for normal authentication. It is kept only as an emergency recovery credential in case the personnel login system becomes unavailable. If none of these authentication methods are provided, the request is treated as an unauthenticated USER request. Such requests do not receive access to any of the protected endpoints provided by this service.

### **5.4.2 Personnel Login and Session Tokens**

Following the decentralized personnel authentication model introduced in Section 3.2.4, this service provides a login endpoint that accepts a personnel identifier and PIN. To reduce the risk of brute force attacks, the endpoint applies two separate rate limits. One limit is applied to the client\'s IP address, while the other is applied to the personnel identifier being targeted. This dual rate limiting approach is important because a numeric PIN has fewer possible combinations than a typical password. An attacker could otherwise avoid an IP based limit by sending login attempts from many different addresses against the same account. By limiting both the source address and the target identifier, repeated guessing attempts are restricted more effectively.

When login is successful, the service returns a signed, time limited session token. This token is described further in Section 5.2.4. The client then includes this token in the session token header for all future requests during the active session. A valid token alone is not enough to guarantee continued access. For every request, the service also checks the current status of the personnel record associated with that token. If the user\'s credential has been revoked after the token was issued, the request is rejected even if the token has not expired and its signature remains valid. The system clearly separates authentication failures from authorization failures. A revoked or invalid credential results in an authentication failure. In this case, the client must remove the token and require the user to log in again. However, if a valid user attempts to access an endpoint that is not allowed for their role, the service returns an authorization failure. This does not invalidate the user\'s token, since the credential itself remains valid. An earlier implementation treated both cases in the same way. As a result, a rescue team member attempting to access a headquarters only screen was logged out completely instead of simply being denied access to that specific feature. This issue was identified during testing and corrected by returning separate status codes for authentication and authorization failures. The client applications described in Sections 5.5 and 5.6 handle these two cases separately.

### **5.4.3 Message and Field Report Endpoints**

The endpoints described in this section handle rescue related data. This includes data that originally comes from the unauthenticated victim system described in Section 5.1, as well as information created by rescue team members during operations.

Rescue team and headquarters roles can retrieve the list of messages stored on a node. These roles can also create messages directly through this authenticated service. This feature is useful when a rescue team member needs to submit a request on behalf of someone who does not have access to a device. The synchronization role can also access message listing, since this endpoint was used by the earlier synchronization implementation for the message table. It remains available as a legacy path alongside the dedicated synchronization endpoints described in Section 5.4.6.

Message claiming follows the same precedence rule used during synchronization in Section 5.2.3. A message that has already been claimed cannot be claimed again. Instead, the response informs the user that the message has already been claimed and identifies the person who claimed it. When a claim is successfully created, the recorded identity is taken from the authenticated personnel identifier associated with the user\'s session token. This is preferred over any identifier provided in the request body, ensuring that the claim is always linked to the account that actually performed the action. The identifier from the request body is used only when authentication is performed using the emergency static API key, since this method does not provide an associated personnel identity.

Field reports submitted by rescue personnel to headquarters, referred to in the codebase as ground station uplink messages, can be created by both rescue team and headquarters roles. These reports can also be viewed by rescue team members, rather than being restricted only to headquarters. This access behaviour was a deliberate correction made after testing. An earlier version allowed only headquarters users to view reports, which prevented rescue team members from seeing their own previously submitted reports in the same application where they created new ones. Since this restriction did not provide a security benefit, the access rules were updated so that rescue personnel can view their own submitted report history.

### **5.4.4 Personnel Management**

Creating, viewing, and revoking personnel credentials are restricted exclusively to the headquarters role. This follows the design principle that only headquarters should have the authority to grant or remove access permissions, rather than individual rescue team members. When a new personnel record is created, the system generates a plaintext PIN. This PIN is returned only once in the response to the creation request. It is not stored or made available again in plaintext after that point. This follows the credential management approach described in Section 3.2.4. The Ground Control Center, described in Section 5.6, is responsible for displaying this generated PIN to the operator immediately after creation. The operator can then securely provide the PIN to the assigned rescue team member.

### **5.4.5 Announcements**

Headquarters personnel can create announcements containing a title, message content, and priority level. These announcements are intended to provide instructions and updates to rescue team members during operations. The announcement list can be accessed by rescue team, headquarters, and synchronization roles. This is because announcements are operational information intended for authenticated rescue personnel. Following the no read back principle established for the victim plane in Section 5.1, announcements are never made available through the unauthenticated user interface. A person submitting a request through the captive portal cannot access or retrieve these announcements.

### **5.4.6 Inter Node Synchronization Endpoints**

For each of the five replicated tables described in Section 5.2.3, this service provides a separate synchronization endpoint. These endpoints are accessible only to the synchronization role and return records that were added or updated after a timestamp provided by the requesting node. These endpoints act as the server side component of the pull based synchronization process described in Section 5.2.2. Instead of using the same general data endpoints accessed by human users, synchronization uses dedicated endpoints for each table. This keeps the synchronization process separate from the rescue and headquarters applications, both in the code structure and in the access control design. It also allows all replicated tables to follow the same delta based data retrieval method.

### **5.4.7 Health Endpoint**

The system provides a single unauthenticated health endpoint that returns the current operational status of a node. This includes information such as whether an Auxiliary Module is connected, the latest GPS fix and battery readings, node uptime, the current system clock source, message and database record counts, and the peer nodes currently considered reachable according to Section 5.2.1. The endpoint also reports any degraded nodes that the system has detected through relayed fallback beacons, as described in Section 3.3.4. Unlike the other endpoints in this section, this endpoint does not require authentication. This open access is intentional because the endpoint is designed only as a basic liveness and diagnostic check rather than a source of sensitive information. The information provided is not considered confidential, as it represents data that can already be observed through the node\'s normal broadcast behaviour.

### **5.4.8 Security Headers**

Every response generated by this service, regardless of the endpoint being accessed or whether the request succeeds or fails, passes through a middleware layer that adds security related HTTP headers. These headers include a restrictive Content Security Policy, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, and Strict-Transport-Security. The Strict-Transport-Security header instructs browser based clients to always use HTTPS when connecting to this service in the future and prevents automatic fallback to plain HTTP. This additional protection strengthens the transport security of the authenticated service. It differs from the unauthenticated victim plane, where the use of plain HTTP was a deliberate design decision discussed in Section 5.1.1.

**5.5 Rescue Personnel Application**
------------------------------------

This section describes the rescue team mobile application implemented in the rescue\_app directory of the drone-network-system repository. It is a Flutter application that provides rescue personnel with access to victim requests, field reports, and headquarters announcements through the authenticated API service described in Section 5.4.

**Figure 5.6: Rescue Personnel Application screen map ui**

### **5.5.1 Application Structure**

The application uses the Provider state management pattern. A single MessageProvider instance is created at the application root and shared across all screens through Flutter\'s dependency injection mechanism. This avoids the need for each screen to maintain its own separate copy of message and announcement data.

Navigation is organized around four permanent tabs shown through a bottom navigation bar: Victim Requests, HQ Uplink, Announcements, and Settings. The Requests tab also displays a badge showing the current number of unclaimed messages. This gives rescue team members a quick view of pending tasks without needing to open the screen.

### **5.5.2 API Communication and Host Restriction**

All communication with a node\'s authenticated API is handled through a dedicated API client. This client is shared with the Ground Control Center described in Section 5.6. Instead of trusting only a specific host address, the client validates the node\'s certificate against a fleet certificate authority loaded by the user through the Settings screen. This follows the same approach used by the Ground Control Center, described in Section 5.6.2. This design corrects an earlier Phase 1 implementation. In Phase 1, the client accepted any certificate presented by a fixed host address without checking whether the certificate was issued by the fleet certificate authority. As a result, any device that responded at that address, including an evil twin access point, could be trusted incorrectly.

A clearly labelled development only option allows certificate validation to be relaxed for bench testing. This option is disabled by default and is not intended for normal deployments.

Authentication uses the personnel credential system described in Section 3.2.4 and Section 5.4.2. This replaces the earlier approach of relying only on a static API key. However, a clearly labelled break glass API key is still available in the Settings screen. It can be used if the personnel login system becomes unavailable, matching the same fallback mechanism used by the Ground Control Center described in Section 5.6.2. The API client also converts failures into a small set of specific exceptions. These include authentication failures, rate limit responses, and general server errors. This allows each screen to display an appropriate error message instead of showing the same generic message for every failure.

### **5.5.3 Victim Requests Screen**

This screen retrieves and displays the complete list of messages available on the node to which the application is currently connected. Each message is shown as a card containing its claim status, submission time, message content, and location information when available. A rescue team member can claim an unclaimed request directly from this screen. After claiming, the request is shown as claimed until the data is refreshed from the node. If a message was submitted in encrypted form, as described further in Section 5.5.6, the screen displays the decrypted content when a suitable private key is configured. Otherwise, it shows an indication that the message cannot be decrypted.

### **5.5.4 HQ Uplink and Announcements Screens**

The HQ Uplink screen allows rescue team members to create and submit field reports to headquarters. Before submission, the user can optionally attach the device\'s current GPS location using the platform\'s location services. The Announcements screen retrieves and displays messages sent from headquarters through the endpoint described in Section 5.4.5. This allows rescue personnel to receive operational instructions and updates provided by the ground station operator.

### **5.5.5 Settings Screen**

The Settings screen allows users to configure the node address used by the application, the static API key required for authentication as described in Section 5.5.2, and the RSA private key used for message decryption where applicable, as described in Section 5.5.6. All of these values are stored using Flutter\'s secure storage facility rather than regular application preferences, providing safer storage for sensitive configuration data.

### **5.5.6 Message Decryption**

The application includes a dedicated service for decrypting messages that were encrypted using RSA-OAEP with SHA-256. This matches the optional client side encryption feature on the victim plane described in Section 5.1.5. If a message is not marked as encrypted, the decryption service does not perform any action. If the message is encrypted, the service reads the user configured PEM-format private key and attempts to decrypt the content. If decryption fails, the application displays a separate error state for that message. This prevents a failed decryption attempt from being confused with a normal plaintext message.

**5.6 Ground Control Center**
-----------------------------

This section describes the Ground Control Center, a Flutter desktop application used by the ground station operator. It is implemented in the gcc\_app directory of the drone-network-system repository and packaged as an installable Windows application, following the framework decision discussed in Section 3.4.

While the rescue personnel application described in Section 5.5 is designed for individual rescue team members working with a single node, the Ground Control Center supports the wider coordination responsibilities of the ground station operator, as described in Section 3.2.4.

![](media/image18.png){width="4.777777777777778in" height="5.079364610673665in"}

Figure 5.7 - Ground Control Center Screen Map

### **5.6.1 Connectivity Model**

Following the decentralization principle established in Chapter 3, the Ground Control Center does not connect to the entire drone fleet at once. Instead, it connects to the single drone node whose Wi-Fi access point is currently within range of the operator\'s laptop. All communication is performed only with that connected node. The information shown by the application about other nodes in the fleet depends on the latest synchronization completed by the connected node, as described in Section 5.2. Therefore, the application displays the age of each dataset instead of presenting the information as if it is always live. This is an intentional design choice. The interface is designed to clearly show operators how recent or outdated their information is, rather than hiding this limitation behind a typical live dashboard appearance.

A persistent connection indicator in the navigation bar displays the currently connected node and the identity of the authenticated operator. It also provides a clear visual difference between connected and disconnected states.

### **5.6.2 Authentication**

The Ground Control Center uses the same personnel authentication system described in Section 3.2.4 and implemented in Section 5.4.2. An operator logs in using a personnel identifier and PIN through a login dialog. After successful authentication, the application receives a session token, which is used for all further requests. A static, clearly labelled break-glass API key is also available in the Settings screen. This provides an alternative authentication method that operates independently from the personnel credential system and is intended only as a fallback option.

Unlike the rescue personnel application described in Section 5.5, the Ground Control Center performs full certificate validation using a specific fleet certificate authority provided by the operator. A connecting node\'s certificate must be successfully verified against this trusted authority before communication is allowed. If certificate verification fails, such as when a node certificate does not match the expected authority, the application presents this as a separate and clearly explained security related failure. It is identified as a possible indication of an impersonating node rather than being treated as a general connection error. The application also provides an option to disable this certificate validation for development and testing purposes. This option is separated from the normal deployment behaviour and is not enabled by default.

### **5.6.3 Map and Offline Mission Planning**

Since internet connectivity cannot be assumed at a disaster site, the map screen uses offline map tiles stored in a pre downloaded tile package selected by the operator through the Settings screen. It does not depend on any online map service. After loading the map, the application displays overlays for node locations, victim message locations, and Emergency Application check in locations, as described in Sections 3.2.5 and 5.7.

The application also provides a separate planning mode that allows the operator to place named advisory markers on the map with an associated coverage radius. These markers are created by selecting a location directly on the map and are intended to support deployment planning and ongoing operations, such as identifying a planned drone position and its expected coverage area. These planning markers are stored only on the operator\'s local machine. They are not transmitted to any drone node and are not synchronized across the network. This keeps them separate from operational data, such as victim messages, which is shared across the fleet through the synchronization mechanism described in Section 5.2.

### **5.6.4 Live Feed, Nodes, and Announcements**

The Live Feed screen displays victim messages available on the currently connected node in a continuously updated list. The Nodes screen displays the health and connectivity information provided by the health endpoint described in Section 5.4.7. This node information also includes any degraded nodes detected through relayed fallback beacons, as described in Section 3.3.4. The Announcements screen allows an authenticated headquarters operator to create and broadcast announcements using the endpoint described in Section 5.4.5. These announcements are later received by rescue team members through the mechanism described in Section 5.5.4 after synchronization has distributed them across the fleet.

### **5.6.5 Personnel Management**

Following the credential model described in Section 3.2.4, an authenticated headquarters operator can create new personnel credentials directly from this application. The generated PIN is displayed only once at the time of creation and cannot be viewed or recovered later, matching the server side behaviour described in Section 5.4.4. The personnel management screen shows each individual\'s current status and provides an option to revoke credentials. The interface also clearly informs the operator that a revocation is applied to other nodes only after they complete their next synchronization cycle. This prevents the operator from assuming that a revocation becomes active across the entire fleet immediately.

### **5.6.6 Drone Control**

A dedicated tab is reserved for monitoring and, when safety conditions allow, controlling the system owned drone through DRONE\_S\'s MAVLink gateway, as introduced in Sections 3.1 and 3.2.4. In the current implementation, this tab intentionally works as a preparation interface rather than an active control interface. It displays the specific hardware identification steps that must be completed and documented before telemetry and control features can be enabled. This follows the staged implementation approach described in Chapter 4. The interface also clearly states that this restriction applies only to the system owned drone. Volunteer operated drones are used only as communication platforms and do not support flight control integration under any circumstances. The screen already supports the planned distinction between the two possible connection paths to DRONE\_S\'s gateway once the feature becomes active. A direct connection is used when the operator\'s laptop is connected to DRONE\_S\'s own access point. A mesh relayed connection is used when the operator is connected to one of the volunteer nodes instead. The application identifies and displays which connection path is currently applicable based on the node to which the Ground Control Center is connected.

### **5.6.7 Shared Code with Other Applications**

Following the framework approach discussed in Section 3.4, this application uses a shared Dart package. The same package is also used by the rescue personnel application described in Section 5.5 and the Emergency Application described in Sections 3.2.5 and 5.7. This shared package provides common data models and the API client used to communicate with a node\'s authenticated service. As a result, changes or improvements to the backend data structure can be made in one shared location instead of being separately implemented across each client application. For example, a future update to align the application data models with the backend schema, such as the outstanding alignment issue discussed in Section 5.5.7, can be handled centrally. This reduces duplicated work and avoids inconsistencies between the different system applications.

**5.7 Emergency Application**
-----------------------------

This section describes the Emergency Application, implemented in the emergency\_app directory of the drone-network-system repository. The application provides the background location logging and BLE-based drone detection functionality introduced conceptually in Section 3.2.5. A review of the actual implementation identified one difference between the conceptual description presented in Chapter 3 and the application\'s current behaviour. This difference is explained in Section 5.7.6, together with the reasoning documented in the application\'s source code for why the current approach was deliberately chosen instead of a fully automatic alternative.

![](media/image19.png){width="6.296875546806649in" height="5.129886264216973in"}

Figure 5.8: Emergency Application screen and service map

### **5.7.1 Background Location Logging**

The application records the device\'s location periodically using Android\'s WorkManager background task scheduler. By default, it is configured to log the location twice per day. This interval is presented as a target rather than a guarantee because WorkManager supports a minimum scheduling interval of fifteen minutes, and the Android operating system may delay scheduled tasks depending on the device\'s battery level and usage conditions. This limitation is clearly explained in both the application\'s user interface and its documentation. Since a twice daily interval is difficult to verify during development and testing, the logging interval is configurable. The application also provides a manual **\"Log a Point Now\"** option, allowing developers and testers to record a location immediately or use a shorter interval without changing the intended production behaviour. Each recorded location includes the latitude, longitude, accuracy, and a UTC timestamp. These records are stored in persistent local storage on the device. Because the background task runs in a separate execution environment and cannot access the application\'s in memory state, it writes directly to local storage. This ensures that location logging continues even when the application\'s user interface is not running.

### **5.7.2 Drone Detection - Armed Watch Mode**

Instead of scanning continuously from the moment the application is installed, the current implementation requires the user to manually enable an **\"armed\" watch mode** from the application interface. When this mode is enabled, the application starts an Android foreground service and displays a persistent, low priority notification indicating that it is actively monitoring for nearby rescue drones. It then begins a Bluetooth Low Energy (BLE) scan filtered to the fixed service identifier advertised by the Auxiliary Module firmware described in Section 5.3.4.

This approach is a deliberate response to an Android platform limitation rather than a design preference. Android does not allow an application to perform continuous background BLE scanning while the screen is off unless it runs as a foreground service. For this reason, the application requires the user to explicitly enable the watch mode, and the persistent notification remains visible while scanning is active. A fully passive, low power scanning approach that would not require user interaction was considered and is documented as a future improvement. However, it has not been implemented in the current version. As a result, users who have not enabled the armed watch mode will not receive notifications when a nearby drone is detected, although the background location logging described in Section 5.7.1 continues to operate independently.

When the scan detects a matching BLE advertisement while the watch mode is active, the application displays a high priority system notification. This notification is separate from the foreground service notification and informs the user that a rescue drone has been detected. When the user taps the notification, the application opens a dedicated **\"Drone Found\"** screen. From there, the user is guided to connect to the corresponding Wi-Fi network and continue with the upload process described in Section 5.7.4. The use of a scan filter based on the service identifier is not only an optimization but also a functional requirement. Android allows reliable background BLE scanning only when the scan targets a known service identifier, meaning an unfiltered scan would not operate reliably in the background.

### **5.7.3 Network Routing to the Drone Access Point**

Field testing identified an important issue that is handled by a dedicated component in the application. A drone node\'s Wi-Fi access point is intentionally designed without internet connectivity. Because of this, an Android device that has mobile data enabled does not automatically use the drone\'s Wi-Fi network as its default network connection. Instead, the device may continue sending the application\'s network requests through the cellular connection, where the drone node\'s local IP address cannot be reached. If this issue is not handled, both the check in upload and, more importantly, an SOS submission can fail even though the user\'s phone is connected to the drone\'s Wi-Fi network. In this situation, the user receives no indication that the request has failed.

This is considered a particularly important issue for the Emergency Application. Unlike rescue personnel using the application described in Section 5.5 or ground station operators using the Ground Control Center described in Section 5.6, members of the public cannot be expected to understand how Wi-Fi and mobile data routing interact. They should not be expected to manually disable mobile data before requesting help through the drone network. To solve this problem, the application explicitly binds its network traffic to the Wi-Fi interface after connecting to a drone\'s access point. This overrides Android\'s default routing decision for the application, ensuring that check-in uploads and SOS requests described in Section 5.7.4 are sent through the drone\'s local Wi-Fi network even when mobile data remains enabled.

### **5.7.4 Check-In Upload and SOS**

After connecting to a drone\'s Wi-Fi network, the application uploads its locally stored location history, described in Section 5.7.1, to the connected node using the check in endpoint described in Section 5.1.7. If the user also selects the SOS option, this information is sent together with the location history. As described in Section 5.1.7, the node creates both a check-in record and a normal victim message. This ensures that an SOS submitted through the Emergency Application follows the same rescue team workflow described in Section 5.5.3 as a request submitted through the captive portal.

The application also provides a dedicated screen where users can review their locally stored location history before uploading it. This allows users to see what information the application has collected about them. A separate Settings screen allows location logging to be disabled completely. When logging is disabled, the background task described in Section 5.7.1 still runs according to its normal schedule, but it does not record any location data. This behaviour follows the check implemented in LocationLogger.captureOnce().

**5.8 Security Architecture**
-----------------------------

This section presents the system\'s security architecture as a whole. It brings together the security mechanisms introduced throughout Sections 5.1 to 5.7 and explains how they work together. It also identifies the assets the system protects, the expected threats, and the remaining risks that still exist even after the implemented security measures.

### **5.8.1 Protected Assets and Their Relative Priority**

The system\'s security design is based on five categories of protected assets. These assets are intentionally ranked by importance because, in a disaster response system operating with limited resources and time, not every security property can be given the same priority. This ranking guides the design decisions discussed throughout this chapter.

The highest priority is the integrity of victim messages and rescue team claims. Messages must be received exactly as they were submitted, and rescue team claims must be reliable and not be changed without authorization. Rescue teams must be able to trust the information presented to them. The second priority is the integrity and safety of the drone control link used by DRONE\_S\'s MAVLink gateway. Protecting this communication is important because unauthorized flight commands could create physical safety risks. The third priority is the protection of personnel credentials and the fleet wide cryptographic trust root that supports them. If these are compromised, an attacker could impersonate rescue personnel or create forged data that appears to come from legitimate drone nodes. The fourth priority is the availability of the network. The system should continue operating and exchanging information even when parts of the network become unavailable. The fifth priority is the confidentiality of victim message content. This lower ranking is a deliberate design decision. In this system, a rescue request that successfully reaches rescuers is considered more valuable than one that remains confidential but fails to arrive, or is delayed because of security measures that make submission more difficult. This priority is the reason for the victim-plane transport design described in Section 5.1.1.

### **5.8.2 Adversary Model**

The system\'s threat model considers four main types of adversaries. The first is an unauthorized local user. This is anyone within range of a node\'s Wi-Fi or Bluetooth Low Energy (BLE) signal who is not a legitimate victim, rescue team member, or headquarters operator. Such a person may attempt to access data, submit fake requests, or interfere with normal system operation. The second is a captured drone. In this scenario, an attacker gains physical possession of a drone node instead of only being within wireless range. This provides access to the node\'s local database, configuration files, and any cryptographic keys or other sensitive information stored on the device. The third is a spam or flooding attacker. This attacker attempts to reduce the system\'s availability by sending a large number of requests. These requests may target either the victim submission service described in Section 5.1 or the personnel login endpoint described in Section 5.4.2. The fourth is an evil twin access point attacker. This attacker attempts to imitate a legitimate drone node\'s Wi-Fi network or authenticated API service. The goal is to trick client devices into connecting to the fake node so that traffic can be intercepted or manipulated.

### **5.8.3 The Five-Plane Architecture**

The system\'s security architecture is divided into five separate security planes. Each plane has different security requirements and uses different protection mechanisms. Instead of applying the same security policy everywhere, the system applies security measures that match the purpose and risks of each plane.

The victim plane, described in Section 5.1, is intentionally unauthenticated and does not use transport layer encryption. Instead, every submitted message is cryptographically signed when it is received, and both per-IP and global rate limiting are applied. This follows the asset priorities described in Section 5.8.1, where message integrity and system availability are considered more important than transport-layer confidentiality.

The rescue and headquarters application plane, described in Sections 5.4 to 5.6, is protected using TLS encryption and role based access control based on the four roles introduced in Section 5.4.1. The Ground Control Center also performs certificate validation against the fleet certificate authority, as described in Section 5.6.2. The rescue personnel application currently provides a lower level of protection by validating only the expected host address rather than the certificate itself, as discussed in Section 5.5.2. This is a known limitation and is examined further in Section 5.8.7.

The inter node plane, described in Section 5.2, protects communication between drone nodes. Every synchronized record is cryptographically signed, and inter node communication is authenticated using a dedicated authentication value. Both are derived from a cryptographic key that is used only for this purpose, as described in Section 5.8.4. Replay attacks are also prevented using the monotonically increasing beacon counter described in Section 5.2.1.

The drone control plane applies only to DRONE\_S\'s MAVLink gateway. As described in Section 5.6.6, this functionality has not yet been fully implemented. Instead, the required security measures have been identified and must be completed before any flight control features are enabled.

The physical capture plane considers the possibility that an attacker gains physical access to a drone node instead of only communicating with it over the network. The risks associated with physical capture and the remaining limitations are discussed in Section 5.8.8.

### **5.8.4 Cryptographic Key Separation**

The system uses three independent cryptographic keys. Each key is derived from a single fleet wide master secret using HKDF with SHA-256 and a different purpose specific context string. Each key protects a different part of the system. The first key is used to sign every record synchronized across the five replicated tables described in Section 5.2.3. The second key is used to authenticate communication between drone nodes on the ad hoc mesh network. It protects both the presence beacons described in Section 5.2.1 and the pull synchronization requests described in Section 5.2.2. The third key is used to sign the personnel session tokens described in Section 5.8.5. Using three purpose specific keys instead of a single shared key improves security because compromising one key does not allow an attacker to forge data protected by the other keys. At the same time, deriving all three keys from one master secret simplifies deployment, since each node only needs to store and receive a single fleet wide secret rather than three separate secrets.

### **5.8.5 Personnel Authentication**

A personnel credential consists of a unique identifier and a PIN. The PIN is generated when the credential is created and is never stored in plaintext afterward. Instead, only a PBKDF2 derived hash with a unique salt for each credential is stored on the nodes. When a user successfully logs in, the credential is exchanged for a short lived session token. This token is signed using HMAC and can be verified by any node using the shared token signing key described in Section 5.8.4. The node that verifies the token does not need to be the same node that originally issued it. For every authenticated request, the system checks both the token\'s signature and its expiry time. It also checks the current status of the associated personnel record. This ensures that a credential revoked after token creation is rejected, even if the token itself is still valid and has not expired, as described in Section 5.4.2. The login endpoint applies two separate rate limits: one based on the client\'s IP address and another based on the personnel identifier. This provides additional protection because numeric PINs have lower complexity compared with traditional passwords and are more vulnerable to repeated guessing attempts.

### **5.8.6 Message and Record Integrity**

Every message received through the victim plane is cryptographically signed when it is stored. This signature is created using the message signing key described in Section 5.8.4, regardless of whether the message arrived through an encrypted or unencrypted connection, as described in Section 5.1.4. During inter node synchronization, every received record is checked against its signature before being accepted. If a record fails verification, it is discarded and a log entry is created instead of silently accepting invalid data, as described in Section 5.2.3. The claimed-status precedence rule is applied both during synchronization and when a message is claimed through the authenticated API described in Section 5.4.3. This prevents a message that has already been claimed from being incorrectly changed back to an unclaimed state by an outdated copy received from another node. This protection directly supports the message integrity requirement identified as the highest-priority asset in Section 5.8.1.

### **5.8.7 Transport Security and Certificate Validation**

The authenticated API service described in Section 5.4 uses TLS exclusively for communication. It uses certificates issued by a fleet specific certificate authority created during deployment, rather than relying on a public certificate authority, which may not be reachable in a disconnected disaster environment. The Ground Control Center validates each connected node\'s certificate against this fleet certificate authority directly, as described in Section 5.6.2. If the certificate validation fails, the application clearly reports this as a possible node impersonation attempt, matching the evil-twin attacker scenario described in Section 5.8.2. The rescue personnel application currently provides a lower level of protection. As described in Section 5.5.2, it only checks whether the connection is made to the expected host address instead of validating the presented certificate against the fleet certificate authority. This approach does not provide the same level of protection against an impersonating node. This limitation is identified as a remaining security gap and will be addressed by updating the application to use the same certificate validation approach as the Ground Control Center.

### **5.8.8 Rate Limiting, Audit Logging, and Physical Capture**

The system uses multiple rate limiting mechanisms to reduce the impact of spam and flooding attacks described in Section 5.8.2. The victim plane applies both per IP and global rate limits, as described in Section 5.1.3. The personnel login system applies separate rate limits based on both IP address and personnel identifier, as described in Section 5.8.5. The system also maintains audit logs for important security related events. These include authentication failures, accepted or rejected inter node records, and personnel claim or revocation actions. These logs provide a history that can be used to investigate events on a node, regardless of whether the operation was successful or rejected.

Physical capture of a drone node remains a security risk that cannot be completely eliminated by the mechanisms described above. If an attacker gains access to a node, they can access its local database, including the plaintext content of victim messages stored on that device. This is a result of the confidentiality last priority described in Section 5.8.1, where message availability and integrity are considered more important than encryption of stored message content by default. A captured node also exposes any cryptographic material stored on it, including the node certificate, private key, and the three purpose separated keys described in Section 5.8.4. The system addresses this risk through operational procedures rather than complete technical prevention. A captured node\'s certificate can be revoked through the fleet certificate authority, and the fleet master secret can be rotated to generate a new set of derived keys for the remaining nodes. However, these actions cannot protect information that was already accessed from the captured device. Therefore, physical capture remains a known residual risk, and the system does not consider it fully eliminated.

**Chapter 6: Testing and Results**
==================================

### **6.1 Unit and Component-Level Testing**

This section describes the automated code level test suites used for different system components. These tests are executed independently of the physical drone hardware. They are run during normal software development and do not require a real field deployment.

### **6.1.1 Backend Test Suite**

The backend test suite is implemented using **pytest** for the FastAPI service described in Chapter 5. It tests both the victim plane and the authenticated API separately, using an in-memory or temporary database instead of the node\'s actual SQLite database.

Tests for the victim plane, described in Section 5.1, verify that the captive portal form is served correctly. They also confirm that the platform specific captive portal detection probes described in Section 5.1.2 return the expected responses. The tests verify that submitted messages are stored correctly and are signed successfully. The test suite also confirms that the public key endpoint returns a \"not found\" response when end to end encryption is disabled. It verifies that a check in containing an SOS flag creates both a check in record and a victim message, as described in Section 5.1.7. Another test confirms that the victim plane does not provide any endpoint for reading submitted data back, directly verifying the no read back principle described in Section 5.1.7 and used in the security architecture in Section 5.8.3.

Rate limiting tests verify that both the per IP and global limiters described in Section 5.1.3 reject requests once their configured limits are exceeded. These are tested directly against the rate-limiting implementation instead of only through complete request flows.

Tests for the authenticated API, described in Section 5.4, verify the complete personnel credential lifecycle described in Sections 5.4.2 and 5.8.5. This includes credential creation, login, and session token generation. The suite also checks that forged or modified tokens are rejected and that expired tokens are handled differently from invalid tokens. This confirms the distinction between authentication and authorization failures described in Section 5.4.2. Additional tests verify that the personnel login rate limiting works correctly during repeated failed login attempts, as described in Section 5.8.5. Other tests confirm the announcement workflow described in Section 5.4.5, verify that the health endpoint correctly reports the Auxiliary Module status described in Section 5.4.7, and ensure that rescue personnel can view the field reports they previously submitted, as described in Section 5.4.3. The test suite also confirms that the inter node synchronization endpoints described in Section 5.4.6 require the correct authentication header and correctly filter records using the since timestamp cursor described in Section 5.2.2.

A separate test module focuses on the conflict resolution rules described in Section 5.2.3. These tests verify that a new synchronized message is stored correctly with its originating node recorded. They confirm that messages with invalid signatures are rejected immediately. The tests also verify that a claimed message cannot be replaced by an incoming record marked as new and that, if two different claims exist for the same message, the earlier claim is retained. Additional tests confirm that a revoked personnel record cannot be replaced by an active version received from another node. They also verify that, when neither personnel record is revoked, the most recently updated record is kept. The suite checks that tampered personnel records are rejected in the same way as tampered messages. It also confirms that announcements behave as append only records and that replayed presence beacons with non increasing counters are rejected by the beacon parser described in Section 5.2.1.

### **6.1.2 Firmware Bench Tests**

The Auxiliary Module firmware, described in Section 5.3, is verified using a documented set of bench-level tests rather than an automated unit test suite. This approach reflects the practical nature of firmware development, where direct interaction with hardware components such as the GPS receiver, LoRa module, and battery monitor cannot be tested as easily as a software only service. The bench tests verify that the firmware correctly acquires GPS fixes and parses NMEA data from the GPS module. They also confirm that the BLE advertisement is structured correctly, including verification of the service UUID placement described in Section 5.3.3. Additional tests verify that the firmware correctly detects the loss of heartbeat messages from the Main Compute Unit and performs the one way transition into the fallback state described in Section 5.3.2. The tests also confirm that fallback beacons are assembled correctly and transmitted as specified in Section 5.3.5.

### **6.1.3 Client Application Test Suites**

Each Flutter application maintains its own set of widget and unit tests. The rescue personnel application\'s tests verify the login flow described in Section 5.5. They confirm that, when no valid session is stored, the application displays the login screen with the break glass login option clearly visible. The tests also verify that submitting the login form with missing required fields is handled correctly without causing the application to crash. Additional tests confirm that a valid, unexpired session allows the user to enter the main interface directly without logging in again, while an expired session returns the user to the login screen instead of leaving the application in a partially authenticated state. The Ground Control Center includes tests for its application state management. These verify that shared application state behaves correctly, including the mission planning functionality described in Section 5.6.3. The test suite also includes a basic smoke test to confirm that the application\'s main interface loads successfully without errors. The Emergency Application includes unit tests for the Bluetooth Low Energy advertisement parser described in Section 5.7.2. These tests verify that the parser correctly extracts a node\'s identifier and Wi-Fi network name from a raw BLE advertisement payload without requiring actual Bluetooth hardware. Additional tests verify the local storage functionality used by the background location logging mechanism described in Section 5.7.1.

### **6.1.4 Summary**

  ------------------------------------- ------------------------------------------------------------------------ ----------------------------------------------------------------------------------------------------------------
  Component                             Test File(s)                                                             Primary Coverage
  Backend API and victim plane          test\_api.py                                                             Victim plane functionality, rate limiting, personnel lifecycle, health endpoint, and synchronization endpoints
  Synchronization conflict resolution   test\_sync\_conflicts.py                                                 Signature verification, per table conflict resolution rules, and replayed beacon rejection
  Auxiliary Module firmware             TESTS.md (bench procedure)                                               GPS parsing, BLE advertisement structure, fallback state transition, and fallback beacon format
  Rescue Personnel Application          gate\_and\_login\_test.dart, model\_test.dart                            Login flow, session expiry handling, and data model validation
  Ground Control Center                 app\_state\_test.dart, plan\_state\_test.dart, shell\_smoke\_test.dart   Application state management, mission planning state, and overall application shell rendering
  Emergency Application                 ble\_parse\_test.dart, storage\_test.dart                                BLE advertisement parsing and local storage functionality
  ------------------------------------- ------------------------------------------------------------------------ ----------------------------------------------------------------------------------------------------------------

### **6.2 Integration and Hardware Acceptance Testing**

The unit and component level tests described in Section 7.1 verify individual system components separately. However, additional testing is required to confirm that these components operate correctly when deployed on real hardware and working together as a complete system. This section presents the integration test plan created for this purpose. In keeping with the academic transparency followed throughout this report, it should be stated clearly that these integration tests have been fully designed but have not yet been executed and recorded on deployed hardware at the time of writing. The project\'s dedicated test log, maintained to capture dated evidence for each completed test, currently remains as a prepared template without recorded results. This is due to the remaining deployment activities described in Chapter 4 that must be completed before full hardware based validation can begin. The integration test plan is included in detail because it represents a structured and practical verification approach for evaluating the complete system. The current lack of executed hardware test results is also explicitly identified as a limitation in Chapter 8 rather than being left implicit.

**Figure 7.1: Integration test plan overview**

### **6.2.1 Node-Level and Dual-Radio Tests**

The first planned test is a per node soak test. A single node will operate continuously on battery power for ninety minutes, matching the Battery A runtime requirement established in Section 4.2. At fixed intervals, the test will verify that the core services remain active, the user access point remains available, and the node remains connected to the ad hoc mesh described in Section 3.2.2. The test will also confirm that the health endpoint continues updating correctly, that the Auxiliary Module serial connection remains active, and that the system clock correctly switches to GPS derived time after a satellite fix is obtained, as described in Section 3.3.3. Battery A voltage measurements will be recorded at each interval. This allows the actual operating duration to be compared directly with the runtime estimation presented in Section 4.2.1. Any significant difference between the predicted and measured runtime will be documented and investigated rather than ignored.

The second planned test verifies the dual radio separation introduced as a major architectural improvement in Section 3.4. A continuous stream of network pings will be sent to a node\'s user facing access point while two nodes repeatedly perform synchronization over an extended period. The test will be considered successful if users remain connected without any unexpected disconnections and the ping loss remains negligible throughout the test period. This provides direct evidence that the reliability issue caused by the earlier single radio design, described in Section 3.4.1, has been properly resolved in the implemented architecture rather than only addressed conceptually.

### **6.2.2 Mesh Resilience and Authentication Tests**

A planned partition and heal test will evaluate the system\'s behaviour during temporary network separation. One of three nodes will be isolated by disabling its mesh radio. During this isolation period, data will be created independently on the isolated node and one of the remaining nodes, while a claim operation will be performed on the third node. After restoring the isolated node\'s connectivity, the system will be monitored to confirm that all five replicated tables described in Section 5.2.3 converge correctly. The test will be considered successful if all nodes reach a consistent state within two synchronization cycles and no duplicate records are created. This directly verifies the eventual consistency property established as a core design principle in Section 3.1.

A planned authentication lifecycle test will verify the personnel credential system across multiple nodes. The test will begin by issuing a new credential through the Ground Control Center. The credential will then be used to authenticate on a different node from the one that created it, followed by performing an identified claim operation. The credential will then be revoked from the original node, and the second node will be tested to confirm that it rejects further use of the revoked credential only after completing its next synchronization cycle. This verifies the credential propagation delay behaviour described in Section 3.2.4 and Section 5.6.5, rather than assuming that revocation behaviour functions correctly without validation.

### **6.2.3 Fault Tolerance and Public Facing Pipeline Tests**

A planned fallback test will evaluate the system\'s behaviour when a node\'s Main Compute Unit becomes unavailable. The test will simulate this condition by directly removing power from the Main Compute Unit. The test will be considered successful if a neighbouring node\'s Ground Control Center view identifies the affected node as degraded within a defined time window. The displayed information must include the node\'s last known GPS position, both battery readings, and the last cached message received through the relayed LoRa beacon mechanism described in Section 3.3.4. After restoring power to the Main Compute Unit, the test will also confirm that the node correctly returns to normal operation.

A planned end to end test will evaluate the complete Emergency Application discovery pipeline described in Section 5.7. This test will verify the full sequence of events, starting from a locked phone detecting a nearby drone and receiving a notification, followed by connecting to the corresponding access point, and ending with the uploaded check in data appearing on the Ground Control Center map and an associated SOS request becoming available for claiming through the rescue application. This complete workflow is intended to be captured as a single, continuous screen recording because it involves interaction between more independently developed system components than any other individual feature. The recording will provide clear evidence of the complete public-facing rescue request pipeline functioning from detection through response.

### **6.2.4 Field Range and Drone Telemetry Tests**

A planned field test will evaluate the system\'s real world communication range and interference behaviour instead of relying only on manufacturer specifications. The test will include a walking range assessment for the user access point, a maximum distance synchronization test between two nodes using the ad-hoc mesh, and a LoRa beacon reception range test conducted specifically at the radio\'s minimum transmit power setting. The LoRa range test will remain dependent on resolving the regulatory considerations already identified in Section 5.3.1 and carried forward as a limitation in Chapter 8. The field test will also verify that mesh synchronization continues to operate correctly while the system drone\'s own communication hardware is active nearby, addressing potential interference effects separately from regulatory limitations.

A further planned test focuses specifically on DRONE\_S\'s MAVLink gateway. This test is divided into three progressively integrated stages. The first stage is a direct connection bench test, confirming that the Ground Control Center can receive live telemetry when connected directly to DRONE\_S. The second stage is a mesh relay test, verifying that the same telemetry remains accessible when the operator connects to a different node while DRONE\_S is reachable through the ad-hoc mesh network. The final stage is a link cut test, verifying that control actions within the Ground Control Center are automatically disabled within a defined short time window after connectivity with DRONE\_S is lost. Propellers will remain removed during this test and all other MAVLink related testing unless the staged safety requirements described in Section 5.6.6 have been formally completed and approved.

### **6.2.5 Security Drills**

A final planned set of tests will evaluate the security architecture described in Section 5.8 under realistic adversarial conditions. These tests extend beyond the isolated unit tests described in Section 7.1.

The first test will verify that an evil twin access point is rejected by the client applications. The test result will also explicitly document the accepted limitation that the victim portal can still accept connections from any network, as discussed in Section 5.8.3. This behaviour will not be incorrectly presented as either a security failure or a successful protection mechanism.

The second test will verify that forged, expired, and revoked authentication tokens are consistently rejected across all nodes in the fleet. This verification will confirm that the protection works across the system, rather than only on the node that originally issued the token. A further test will evaluate the presence beacon replay protection under real radio conditions. A previously captured synchronization beacon will be retransmitted to verify that the counter based rejection mechanism described in Section 5.2.1 correctly identifies and rejects replayed messages. This ensures the mechanism works in practical conditions rather than only under the simulated conditions used in Section 7.1.1. The MAVLink gateway security test will verify that unsigned or unauthorized control commands are ignored or blocked. This test will also be performed with propellers removed to maintain safety during verification. A flooding resistance test will evaluate whether scripted high volume request attempts are correctly throttled. At the same time, it will confirm that legitimate rescue personnel can continue accessing the system during the attack period. Finally, a repository hygiene check will confirm that no active secrets are stored within version control history. A fresh deployment from the repository will also be verified to ensure that it generates new cryptographic material correctly. It will also confirm that no credentials or keys from development or testing environments are inherited.

### **6.2.6 Backout Criterion**

The integration test plan defines an explicit backout condition to handle failures in the ad-hoc mesh configuration described in Chapter 4.If the dual-radio non-disruption test described in Section 7.2.1 or the partition-and-heal test described in Section 7.2.2 repeatedly fails, the issue will be evaluated on the specific kernel and driver combination used by the deployed hardware. If the failure continues, the test plan requires reverting to the previously documented access point/client role cycling fallback approach. Further testing will not continue until this fundamental networking issue is resolved. After switching back to the fallback configuration, the same two tests must be performed again. This confirms that the alternative approach provides acceptable stability before continuing with the remaining tests in the integration plan.

References for New Literature Review Chapter
============================================

1.  M. Y. Arafat and S. Moh, \"Location-Aided Delay Tolerant Routing Protocol in UAV Networks for Post-Disaster Operation,\" *IEEE Access*, vol. 6, pp. 59891--59906, 2018.

2.  I. Chandran and K. Vipin, \"Multi-UAV networks for disaster monitoring: challenges and opportunities from a network perspective,\" *Drone Systems and Applications*, vol. 12, pp. 1--28, 2024.

3.  V. Hassija, V. Chamola, A. Agrawal, A. Goyal, N. C. Luong, D. Niyato, F. R. Yu, and M. Guizani, \"Fast, Reliable, and Secure Drone Communication: A Comprehensive Survey,\" *IEEE Communications Surveys & Tutorials*, vol. 23, no. 4, pp. 2802--2832, 2021.
