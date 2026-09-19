# XSD-контракт

```xml
<xs:schema
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    targetNamespace="http://example.com/vet/patients"
    xmlns:tns="http://example.com/vet/patients"
    elementFormDefault="qualified">

    <!-- Вид животного -->
    <xs:simpleType name="AnimalType">
        <xs:restriction base="xs:string">
            <xs:enumeration value="DOG"/>
            <xs:enumeration value="CAT"/>
            <xs:enumeration value="BIRD"/>
            <xs:enumeration value="REPTILE"/>
        </xs:restriction>
    </xs:simpleType>


    <!-- ФИО владельца -->
    <xs:simpleType name="OwnerNameType">
        <xs:restriction base="xs:string">
            <xs:minLength value="3"/>
            <xs:maxLength value="100"/>
        </xs:restriction>
    </xs:simpleType>


    <!-- Кличка животного -->
    <xs:simpleType name="PetNameType">
        <xs:restriction base="xs:string">
            <xs:minLength value="1"/>
            <xs:maxLength value="50"/>
        </xs:restriction>
    </xs:simpleType>


    <!-- Номер ветеринарного паспорта -->
    <xs:simpleType name="PassportNumberType">
        <xs:restriction base="xs:string">
            <xs:pattern value="[A-Z]{2}-[0-9]{6}"/>
        </xs:restriction>
    </xs:simpleType>


    <!-- UUID пациента -->
    <xs:simpleType name="UuidType">
        <xs:restriction base="xs:string">
            <xs:pattern
                value="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"/>
        </xs:restriction>
    </xs:simpleType>


    <!-- Данные пациента при регистрации: ID ещё нет -->
    <xs:complexType name="PatientRegistrationType">
        <xs:sequence>
            <xs:element name="ownerName" type="tns:OwnerNameType"/>
            <xs:element name="petName" type="tns:PetNameType"/>
            <xs:element name="animalType" type="tns:AnimalType"/>
            <xs:element
                name="passportNumber"
                type="tns:PassportNumberType"
                minOccurs="0"/>
        </xs:sequence>
    </xs:complexType>


    <!-- Полная сущность Patient -->
    <xs:complexType name="Patient">
        <xs:sequence>
            <xs:element name="id" type="tns:UuidType"/>
            <xs:element name="ownerName" type="tns:OwnerNameType"/>
            <xs:element name="petName" type="tns:PetNameType"/>
            <xs:element name="animalType" type="tns:AnimalType"/>
            <xs:element
                name="passportNumber"
                type="tns:PassportNumberType"
                minOccurs="0"/>
        </xs:sequence>
    </xs:complexType>


    <!-- getPatients: запрос -->
    <xs:element name="getPatientsRequest">
        <xs:complexType>
            <xs:sequence>
                <xs:element
                    name="animalType"
                    type="tns:AnimalType"
                    minOccurs="0"/>
            </xs:sequence>
        </xs:complexType>
    </xs:element>


    <!-- getPatients: ответ -->
    <xs:element name="getPatientsResponse">
        <xs:complexType>
            <xs:sequence>
                <xs:element name="patients">
                    <xs:complexType>
                        <xs:sequence>
                            <xs:element
                                name="patient"
                                type="tns:Patient"
                                minOccurs="0"
                                maxOccurs="unbounded"/>
                        </xs:sequence>
                    </xs:complexType>
                </xs:element>
            </xs:sequence>
        </xs:complexType>
    </xs:element>


    <!-- registerPatient: запрос -->
    <xs:element name="registerPatientRequest">
        <xs:complexType>
            <xs:sequence>
                <xs:element
                    name="patient"
                    type="tns:PatientRegistrationType"/>
            </xs:sequence>
        </xs:complexType>
    </xs:element>


    <!-- registerPatient: ответ -->
    <xs:element name="registerPatientResponse">
        <xs:complexType>
            <xs:sequence>
                <xs:element
                    name="registeredPatient"
                    type="tns:Patient"/>
            </xs:sequence>
        </xs:complexType>
    </xs:element>

</xs:schema>
```
