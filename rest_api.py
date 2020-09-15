from flask import Flask, request, jsonify, Response
from flask_restful import Resource, Api
import json
import os
import random


app = Flask(__name__)
api = Api(app)


db = {}

class Patient(Resource):
    def get(self, patient_id):
        patient_data = db.get(patient_id)
        if patient_data is not None:
            decoded_data = json.loads(patient_data.decode('utf-8'))
            decoded_data["id"] = patient_id
            return jsonify(decoded_data)
        return Response({"error": "unknown patient_id"}, status=404, mimetype='application/json')

    def post(self, patient_id):
        if db.get(patient_id) is not None:
            return Response({"error": "already exists"}, status=403, mimetype='application/json')
        else:
            # convert patient data to binary.
            patient_data = json.dumps({
            "fname": request.form['fname'],
            "lname": request.form['lname'],
            "address": request.form['address'],
            "city": request.form['city'],
            "state": request.form['state'],
            "ssn": request.form['ssn'],
            "email": request.form['email'],
            "dob": request.form['dob'],
            "contactphone": request.form['contactphone'],
            "drugallergies": request.form['drugallergies'],
            "preexistingconditions": request.form['preexistingconditions'],
            "dateadmitted": request.form['dateadmitted'],
            "insurancedetails": request.form['insurancedetails'],
            "score": random.random()
            }).encode('utf-8')
            try:
                db[patient_id]=patient_data
            except Exception as e:
                print(e)
                return Response({"error": "internal server error"}, status=500, mimetype='application/json')
            patient_data = json.loads(patient_data.decode('utf-8'))
            patient_data["id"] = patient_id
            return jsonify(patient_data)


class Score(Resource):
    def get(self, patient_id):
        patient_data = db.get(patient_id)
        if patient_data is not None:
            score = json.loads(patient_data.decode('utf-8'))["score"]
            return jsonify({"id": patient_id, "score": score})
        return Response({"error": "unknown patient"}, status=404, mimetype='application/json')


api.add_resource(Patient, '/patient/<string:patient_id>')
api.add_resource(Score, '/score/<string:patient_id>')


if __name__ == '__main__':
    app.debug = False
    app.run(host='0.0.0.0', port=4996, threaded=True, ssl_context=(("/tls/flask.crt", "/tls/flask.key")))
